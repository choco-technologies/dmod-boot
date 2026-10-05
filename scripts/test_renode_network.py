#!/usr/bin/env python3
"""Check the network of the Renode machine from the host.

Renode connects the board's Ethernet to a TAP interface on the host
(DMBOOT_RENODE_TAP). This script gives the host end of it an address, serves
DHCP on it and then checks, driving the shell on the console UART where the
board side is needed:

- the board's DHCP client gets its lease
- the board pings the host (`ping` in the shell)
- the host pings the board (ICMP echo)
- a telnet session to the board gets a shell that runs `echo <token>`
- the board resolves a name (`nslookup` in the shell) through the dns
  service, with the name server it got from the DHCP lease (option 6) -
  the host answers on UDP port 53 itself

Needs root (TAP address, DHCP and DNS ports, raw ICMP socket) - only the
standard library, no ip/ping/telnet/DNS server tools.

Usage: test_renode_network.py [--tap TAP] [--uart-port PORT] [--timeout SECONDS]
"""
import argparse
import fcntl
import os
import re
import socket
import struct
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_renode_uart import Terminal, check, connect, wait_for_prompt  # noqa: E402

HOST_ADDR = "192.168.100.1"
BOARD_ADDR = "192.168.100.2"
NETMASK = "255.255.255.0"
PREFIX_LEN = 24
TELNET_PORT = 23
DNS_PORT = 53

# Names the host's DNS server knows - everything else is NXDOMAIN
DNS_TEST_NAME = "dmod-boot.test"
DNS_TEST_ADDR = "192.168.100.77"
DNS_MISSING_NAME = "no-such-host.test"
DNS_TTL = 60
DNS_TYPE_A = 1
DNS_CLASS_IN = 1
DNS_RCODE_NXDOMAIN = 3

# Linux ioctls / socket options used to configure the TAP without iproute2
SIOCSIFADDR, SIOCSIFNETMASK, SIOCGIFFLAGS, SIOCSIFFLAGS = 0x8916, 0x891C, 0x8913, 0x8914
IFF_UP = 0x1
SO_BINDTODEVICE = 25


def configure_interface(name, addr, netmask):
    """Give the interface an IPv4 address and bring it up."""
    def ifreq_addr(value):
        return struct.pack("16sH2s4s8s", name.encode(), socket.AF_INET, b"\0\0", socket.inet_aton(value), b"\0" * 8)

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        fcntl.ioctl(sock, SIOCSIFADDR, ifreq_addr(addr))
        fcntl.ioctl(sock, SIOCSIFNETMASK, ifreq_addr(netmask))
        flags = struct.unpack("16sH", fcntl.ioctl(sock, SIOCGIFFLAGS, struct.pack("16sH", name.encode(), 0))[:18])[1]
        fcntl.ioctl(sock, SIOCSIFFLAGS, struct.pack("16sH", name.encode(), flags | IFF_UP))


def wait_for_interface(name, deadline):
    while not os.path.exists(f"/sys/class/net/{name}"):
        if time.monotonic() > deadline:
            raise TimeoutError(f"interface {name} did not appear - is Renode connected to it?")
        time.sleep(0.5)


class DhcpServer(threading.Thread):
    """Answers DHCP DISCOVER/REQUEST on one interface with a single fixed lease."""

    def __init__(self, interface, server_addr, client_addr, netmask):
        super().__init__(daemon=True)
        self.server_addr, self.client_addr, self.netmask = server_addr, client_addr, netmask
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, SO_BINDTODEVICE, interface.encode() + b"\0")
        self.sock.bind(("0.0.0.0", 67))
        self.sock.settimeout(0.5)
        self.acked = threading.Event()
        self.running = True

    def reply(self, request, message_type):
        xid, chaddr = request[4:8], request[28:44]
        packet = (struct.pack("!BBBB", 2, 1, 6, 0) + xid + b"\0" * 8 + socket.inet_aton(self.client_addr)
                  + socket.inet_aton(self.server_addr) + b"\0" * 4 + chaddr + b"\0" * 192 + b"\x63\x82\x53\x63")
        options = [
            (53, bytes([message_type])),
            (54, socket.inet_aton(self.server_addr)),
            (51, struct.pack("!I", 3600)),
            (1, socket.inet_aton(self.netmask)),
            (3, socket.inet_aton(self.server_addr)),
            (6, socket.inet_aton(self.server_addr)),   # DNS server: DnsServer below
        ]
        for code, value in options:
            packet += bytes([code, len(value)]) + value
        self.sock.sendto(packet + b"\xff", ("255.255.255.255", 68))

    def run(self):
        while self.running:
            try:
                data, _ = self.sock.recvfrom(1500)
            except socket.timeout:
                continue
            if len(data) < 240 or data[0] != 1:
                continue
            message_type = self.message_type(data[240:])
            if message_type == 1:      # DISCOVER -> OFFER
                self.reply(data, 2)
            elif message_type == 3:    # REQUEST -> ACK
                self.reply(data, 5)
                self.acked.set()

    @staticmethod
    def message_type(options):
        i = 0
        while i + 1 < len(options) and options[i] != 255:
            if options[i] == 0:
                i += 1
                continue
            if options[i] == 53:
                return options[i + 2]
            i += 2 + options[i + 1]
        return None


class DnsServer(threading.Thread):
    """Answers DNS queries on one interface: DNS_TEST_NAME has one A record, every other name is NXDOMAIN.

    A query for another type of DNS_TEST_NAME (AAAA) gets an empty NOERROR
    answer (NODATA). Records which names it was asked about, and from where.
    """

    def __init__(self, interface, addr):
        super().__init__(daemon=True)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, SO_BINDTODEVICE, interface.encode() + b"\0")
        self.sock.bind((addr, DNS_PORT))
        self.sock.settimeout(0.5)
        self.queries = []
        self.running = True

    @staticmethod
    def parse_question(query):
        """Return (name, qtype, end of question) of a one-question query, or None."""
        if len(query) < 12 or struct.unpack("!H", query[4:6])[0] != 1:
            return None
        labels, pos = [], 12
        while pos < len(query) and query[pos] != 0:
            length = query[pos]
            labels.append(query[pos + 1:pos + 1 + length].decode(errors="replace"))
            pos += 1 + length
        if pos + 5 > len(query):
            return None
        qtype = struct.unpack("!H", query[pos + 1:pos + 3])[0]
        return ".".join(labels).lower(), qtype, pos + 5

    def answer(self, query, name, qtype, question_end):
        found = name == DNS_TEST_NAME
        records = b""
        if found and qtype == DNS_TYPE_A:
            records = (struct.pack("!HHHIH", 0xC00C, DNS_TYPE_A, DNS_CLASS_IN, DNS_TTL, 4)
                       + socket.inet_aton(DNS_TEST_ADDR))
        flags = 0x8180 | (0 if found else DNS_RCODE_NXDOMAIN)   # QR, RD, RA
        header = query[0:2] + struct.pack("!HHHHH", flags, 1, 1 if records else 0, 0, 0)
        return header + query[12:question_end] + records

    def run(self):
        while self.running:
            try:
                query, peer = self.sock.recvfrom(512)
            except socket.timeout:
                continue
            question = self.parse_question(query)
            if question is None:
                continue
            self.queries.append((peer[0], question[0]))
            self.sock.sendto(self.answer(query, *question), peer)


def icmp_checksum(data):
    if len(data) % 2:
        data += b"\0"
    total = sum(struct.unpack(f"!{len(data) // 2}H", data))
    total = (total >> 16) + (total & 0xFFFF)
    total += total >> 16
    return ~total & 0xFFFF


def host_ping(addr, count, timeout=3):
    """Send ICMP echo requests from the host, return how many were answered."""
    ident, payload, answered = os.getpid() & 0xFFFF, b"dmod-boot-renode-test", 0
    with socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP) as sock:
        sock.settimeout(timeout)
        for seq in range(count):
            header = struct.pack("!BBHHH", 8, 0, 0, ident, seq)
            packet = struct.pack("!BBHHH", 8, 0, icmp_checksum(header + payload), ident, seq) + payload
            sock.sendto(packet, (addr, 0))
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                try:
                    data, _ = sock.recvfrom(1024)
                except socket.timeout:
                    break
                icmp = data[(data[0] & 0x0F) * 4:]
                if icmp[0] == 0 and struct.unpack("!HH", icmp[4:8]) == (ident, seq):
                    answered += 1
                    break
    return answered


class TelnetTerminal(Terminal):
    """Terminal over a telnet connection - option negotiation is left unanswered and stripped."""

    IAC_SEQUENCE = re.compile(rb"\xff[\xfb-\xfe].|\xff\xfa.*?\xff\xf0|\xff[\xf0-\xfa]", re.DOTALL)

    def text(self):
        return self.IAC_SEQUENCE.sub(b"", super().text())


def wait_for_lease(term, deadline):
    """Poll `ip addr` on the board until eth0 has the leased address."""
    expected = f"eth0: {BOARD_ADDR}/{PREFIX_LEN}"
    while time.monotonic() < deadline:
        output = term.run("ip addr")
        if output is not None and expected in output:
            return True
        time.sleep(2)
    return False


def check_dns(uart, dns):
    """Resolve names on the board with no server given: the dns service must use the one from the DHCP lease."""
    if not check(uart, f"nslookup -4 {DNS_TEST_NAME}", lambda out: f"Address: {DNS_TEST_ADDR}" in "\n".join(out),
                 f"board resolves {DNS_TEST_NAME} to {DNS_TEST_ADDR} (server from the DHCP lease)"):
        return False
    if (BOARD_ADDR, DNS_TEST_NAME) not in dns.queries:
        print(f"✗ the host's DNS server was never asked about {DNS_TEST_NAME} by {BOARD_ADDR}: {dns.queries!r}")
        return False
    print(f"✓ the query reached the host's DNS server ({HOST_ADDR}:{DNS_PORT})")
    return check(uart, f"nslookup -4 {DNS_MISSING_NAME}", lambda out: "NXDOMAIN" in "\n".join(out),
                 f"board reports {DNS_MISSING_NAME} as a missing name (NXDOMAIN)")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tap", default="tap0")
    parser.add_argument("--uart-port", type=int, default=3456)
    parser.add_argument("--timeout", type=float, default=90,
                        help="seconds to wait for the interface, the shell and the DHCP lease")
    args = parser.parse_args()
    deadline = time.monotonic() + args.timeout

    wait_for_interface(args.tap, deadline)
    configure_interface(args.tap, HOST_ADDR, NETMASK)
    print(f"✓ Host end of {args.tap}: {HOST_ADDR}/{PREFIX_LEN}")
    dhcp = DhcpServer(args.tap, HOST_ADDR, BOARD_ADDR, NETMASK)
    dhcp.start()
    dns = DnsServer(args.tap, HOST_ADDR)
    dns.start()

    uart = Terminal(connect("127.0.0.1", args.uart_port, deadline))
    if not wait_for_prompt(uart, deadline):
        print("✗ No shell prompt on the console UART")
        return 1

    if not wait_for_lease(uart, deadline):
        print(f"✗ eth0 did not get {BOARD_ADDR} over DHCP (server {'acked' if dhcp.acked.is_set() else 'got no request'})")
        return 1
    print(f"✓ DHCP: eth0 leased {BOARD_ADDR}/{PREFIX_LEN}")

    def all_received(out):
        match = re.search(r"(\d+) packets transmitted, (\d+) packets received", "\n".join(out))
        return match is not None and int(match.group(1)) > 0 and match.group(1) == match.group(2)

    if not check(uart, f"ping {HOST_ADDR}", all_received, f"board pings the host ({HOST_ADDR})"):
        return 1

    answered = host_ping(BOARD_ADDR, 3)
    if answered != 3:
        print(f"✗ host pings the board ({BOARD_ADDR}): {answered}/3 answered")
        return 1
    print(f"✓ host pings the board ({BOARD_ADDR}): 3/3 answered")

    telnet = TelnetTerminal(socket.create_connection((BOARD_ADDR, TELNET_PORT), timeout=5))
    if not wait_for_prompt(telnet, time.monotonic() + 30):
        print(f"✗ No shell prompt over telnet ({BOARD_ADDR}:{TELNET_PORT})")
        print(f"Received: {telnet.text()[-500:]!r}")
        return 1
    print(f"✓ telnet {BOARD_ADDR}:{TELNET_PORT} gives a shell prompt")
    token = f"telnet-test-{int(time.time())}"
    if not check(telnet, f"echo {token}", lambda out: token in out, "echo over telnet prints its argument"):
        return 1
    telnet.sock.close()

    if not check_dns(uart, dns):
        return 1

    dhcp.running = False
    dns.running = False
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (TimeoutError, ConnectionError, OSError) as error:
        print(f"✗ {error}")
        sys.exit(1)
