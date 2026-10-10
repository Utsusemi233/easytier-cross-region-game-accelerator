# Optional process-based game experiment

This experiment compares the existing official EasyTier client with a separate Windows sing-box TUN configuration. Selected game processes send new IPv4 TCP connections through Hysteria2 to an authorized private gateway. The gateway reuses an existing, verified WireGuard and UDPspeeder exit path. Other processes, game UDP and physical IPv6 retain local egress.

This is a test procedure, not an additional automatic installer or a LuCI feature. Do not run competing acceleration routes simultaneously. Keep the original profiles and a verified restoration procedure. Use official binaries, check release hashes, and verify both configuration parsing and actual traffic.

Before enabling TUN, obtain real HTTPS responses through a loopback diagnostic proxy. Validate UDP requests and replies separately before extending the scope. A successful proxy connection acknowledgement does not establish successful remote communication.

Test from a fresh game login. Verify the process, scene connection, outbound tag and bidirectional data. Compare game latency on the same network and server, then restore the original configuration and verify its current exit. A detected TCP connection does not establish that every game packet or its displayed latency uses TCP.

Avoid fixed physical client addresses. Actual roaming, failure recovery and resource use still require separate acceptance tests. This experiment does not promise universally lower latency or uninterrupted sessions.

See the [full Chinese procedure and upstream references](PROCESS-GAME-LAB.md). Personal configurations, screenshots and measurements belong in private deployment records.
