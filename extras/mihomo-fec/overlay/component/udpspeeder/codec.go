// UDPspeeder V2 mode-0 wire compatibility. See NOTICE.md for upstream attribution.
package udpspeeder

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"hash/crc32"
	"sync"

	"github.com/klauspost/reedsolomon"
)

const maxData = 32

var gfExp [512]byte
var gfLog [256]int
var rsCache sync.Map

func init() {
	x := 1
	for i := 0; i < 255; i++ {
		gfExp[i] = byte(x)
		gfLog[x] = i
		x <<= 1
		if x&256 != 0 {
			x ^= 0x11d
		}
	}
	for i := 255; i < len(gfExp); i++ {
		gfExp[i] = gfExp[i-255]
	}
}
func mul(a, b byte) byte {
	if a == 0 || b == 0 {
		return 0
	}
	return gfExp[gfLog[a]+gfLog[b]]
}
func inverse(a byte) byte { return gfExp[255-gfLog[a]] }

// Rizzo's original matrix uses powers of alpha as row points. The default
// klauspost matrix uses different points, so a custom parity matrix is required.
func codec(k, p int) (reedsolomon.Encoder, error) {
	if k < 1 || k > maxData || p < 1 || k+p >= 255 {
		return nil, errors.New("udpspeeder: invalid FEC dimensions")
	}
	key := k*256 + p
	if c, ok := rsCache.Load(key); ok {
		return c.(reedsolomon.Encoder), nil
	}
	v := make([][]byte, k+p)
	for row := range v {
		v[row] = make([]byte, k)
		v[row][0] = 1
		if row > 0 {
			for col := 1; col < k; col++ {
				v[row][col] = gfExp[((row-1)*col)%255]
			}
		}
	}
	a := make([][]byte, k)
	for i := range a {
		a[i] = make([]byte, 2*k)
		copy(a[i], v[i])
		a[i][k+i] = 1
	}
	for col := 0; col < k; col++ {
		pivot := col
		for pivot < k && a[pivot][col] == 0 {
			pivot++
		}
		if pivot == k {
			return nil, errors.New("udpspeeder: singular matrix")
		}
		a[col], a[pivot] = a[pivot], a[col]
		scale := inverse(a[col][col])
		for j := range a[col] {
			a[col][j] = mul(a[col][j], scale)
		}
		for row := 0; row < k; row++ {
			if row == col {
				continue
			}
			scale = a[row][col]
			if scale != 0 {
				for j := range a[row] {
					a[row][j] ^= mul(a[col][j], scale)
				}
			}
		}
	}
	parity := make([][]byte, p)
	for row := range parity {
		parity[row] = make([]byte, k)
		for col := 0; col < k; col++ {
			for j := 0; j < k; j++ {
				parity[row][col] ^= mul(v[row+k][j], a[j][k+col])
			}
		}
	}
	c, err := reedsolomon.New(k, p, reedsolomon.WithCustomMatrix(parity), reedsolomon.WithMaxGoroutines(1))
	if err != nil {
		return nil, err
	}
	actual, _ := rsCache.LoadOrStore(key, c)
	return actual.(reedsolomon.Encoder), nil
}

func cook(data, key []byte) ([]byte, error) {
	// CRC32 is big-endian; obscure appends a random IV and its one-byte length;
	// repeating XOR is applied last. This is compatibility, not encryption design.
	var r [1]byte
	if _, err := rand.Read(r[:]); err != nil {
		return nil, err
	}
	ivLen := 4 + int(r[0])%29
	out := make([]byte, len(data)+4+ivLen+1)
	copy(out, data)
	binary.BigEndian.PutUint32(out[len(data):], crc32.ChecksumIEEE(data))
	payloadLen := len(data) + 4
	if _, err := rand.Read(out[payloadLen : payloadLen+ivLen]); err != nil {
		return nil, err
	}
	for i := 0; i < payloadLen; i++ {
		out[i] ^= out[payloadLen+i%ivLen]
	}
	out[len(out)-1] = byte(ivLen)
	for i := range out {
		if len(key) > 0 {
			out[i] ^= key[i%len(key)]
		}
	}
	return out, nil
}
func uncook(data, key []byte) ([]byte, error) {
	if len(data) < 9 {
		return nil, errors.New("udpspeeder: short wire packet")
	}
	out := append([]byte(nil), data...)
	for i := range out {
		if len(key) > 0 {
			out[i] ^= key[i%len(key)]
		}
	}
	ivLen := int(out[len(out)-1])
	if ivLen < 4 || ivLen > 32 || len(out) < ivLen+5 {
		return nil, errors.New("udpspeeder: bad IV")
	}
	end := len(out) - 1 - ivLen
	for i := 0; i < end; i++ {
		out[i] ^= out[end+i%ivLen]
	}
	payload := out[:end-4]
	if binary.BigEndian.Uint32(out[end-4:end]) != crc32.ChecksumIEEE(payload) {
		return nil, errors.New("udpspeeder: checksum mismatch")
	}
	return payload, nil
}

func encodeGroup(seq uint32, packets [][]byte, data, parity, mtu int) ([][]byte, error) {
	size := 4
	for _, p := range packets {
		if len(p) > 65535 {
			return nil, errors.New("udpspeeder: oversized payload")
		}
		size += 2 + len(p)
	}
	if len(packets) == 0 || len(packets) > 200 {
		return nil, errors.New("udpspeeder: invalid group")
	}
	k := data
	best := ((size+k-1)/k + 40) * (k + parity)
	for n := 1; n < data; n++ {
		l := (size + n - 1) / n
		cost := (l + 40) * (n + parity)
		if l <= mtu && cost < best {
			k = n
			best = cost
		}
	}
	shardLen := (size + k - 1) / k
	if shardLen > mtu {
		return nil, errors.New("udpspeeder: FEC shard exceeds MTU")
	}
	blob := make([]byte, k*shardLen)
	binary.BigEndian.PutUint32(blob, uint32(len(packets)))
	pos := 4
	for _, p := range packets {
		binary.BigEndian.PutUint16(blob[pos:], uint16(len(p)))
		pos += 2
		copy(blob[pos:], p)
		pos += len(p)
	}
	shards := make([][]byte, k+parity)
	for i := range shards {
		shards[i] = make([]byte, shardLen)
		if i < k {
			copy(shards[i], blob[i*shardLen:(i+1)*shardLen])
		}
	}
	c, err := codec(k, parity)
	if err != nil {
		return nil, err
	}
	if err = c.Encode(shards); err != nil {
		return nil, err
	}
	out := make([][]byte, len(shards))
	for i, s := range shards {
		out[i] = make([]byte, 8+shardLen)
		binary.BigEndian.PutUint32(out[i], seq)
		out[i][4] = 0
		out[i][5] = byte(k)
		out[i][6] = byte(parity)
		out[i][7] = byte(i)
		copy(out[i][8:], s)
	}
	return out, nil
}

type decodeGroup struct {
	k, p, length int
	shards       [][]byte
	count        int
}

func parseGroup(data []byte) (uint32, int, int, int, []byte, error) {
	if len(data) < 9 {
		return 0, 0, 0, 0, nil, errors.New("udpspeeder: short FEC packet")
	}
	seq := binary.BigEndian.Uint32(data)
	k, p, i := int(data[5]), int(data[6]), int(data[7])
	if data[4] != 0 || k < 1 || k > maxData || p < 1 || p > 64 || k+p >= 255 || i >= k+p || len(data) > 1260 {
		return 0, 0, 0, 0, nil, errors.New("udpspeeder: unsupported FEC packet")
	}
	return seq, k, p, i, data[8:], nil
}
func (g *decodeGroup) add(index int, data []byte) ([][]byte, error) {
	if len(data) != g.length {
		return nil, errors.New("udpspeeder: inconsistent shard length")
	}
	if g.shards[index] != nil {
		return nil, nil
	}
	g.shards[index] = append([]byte(nil), data...)
	g.count++
	if g.count < g.k {
		return nil, nil
	}
	c, err := codec(g.k, g.p)
	if err != nil {
		return nil, err
	}
	if err = c.ReconstructData(g.shards); err != nil {
		return nil, err
	}
	blob := make([]byte, 0, g.k*g.length)
	for _, s := range g.shards[:g.k] {
		blob = append(blob, s...)
	}
	if len(blob) < 4 {
		return nil, errors.New("udpspeeder: short blob")
	}
	n := int(binary.BigEndian.Uint32(blob))
	if n < 1 || n > 200 {
		return nil, errors.New("udpspeeder: invalid blob count")
	}
	out := make([][]byte, 0, n)
	pos := 4
	for j := 0; j < n; j++ {
		if pos+2 > len(blob) {
			return nil, errors.New("udpspeeder: truncated blob")
		}
		l := int(binary.BigEndian.Uint16(blob[pos:]))
		pos += 2
		if l < 4 || pos+l > len(blob) {
			return nil, fmt.Errorf("udpspeeder: invalid conversation packet length")
		}
		out = append(out, append([]byte(nil), blob[pos:pos+l]...))
		pos += l
	}
	return out, nil
}
