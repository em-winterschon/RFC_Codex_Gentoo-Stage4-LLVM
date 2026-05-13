#!/usr/bin/env python3
import argparse
import os
import socket
import struct
import sys
import threading

OP_RRQ = 1
OP_DATA = 3
OP_ACK = 4
OP_ERROR = 5
OP_OACK = 6
ERR_NOT_FOUND = 1
ERR_ACCESS = 2
ERR_ILLEGAL = 4


def packet_error(code, message):
    return struct.pack("!HH", OP_ERROR, code) + message.encode() + b"\0"


def parse_rrq(data):
    if len(data) < 4:
        raise ValueError("short packet")
    opcode = struct.unpack("!H", data[:2])[0]
    if opcode != OP_RRQ:
        raise ValueError("not RRQ")
    parts = data[2:].split(b"\0")
    parts = [p.decode(errors="strict") for p in parts if p]
    if len(parts) < 2:
        raise ValueError("missing filename or mode")
    filename = parts[0]
    mode = parts[1].lower()
    opts = {}
    for i in range(2, len(parts) - 1, 2):
        opts[parts[i].lower()] = parts[i + 1]
    return filename, mode, opts


def safe_path(root, filename):
    filename = filename.lstrip("/")
    path = os.path.realpath(os.path.join(root, filename))
    root = os.path.realpath(root)
    if path != root and not path.startswith(root + os.sep):
        raise PermissionError(filename)
    return path


def is_expected_ack(packet, block):
    return packet == struct.pack("!HH", OP_ACK, block)


def is_tftp_error(packet):
    return len(packet) >= 4 and struct.unpack("!H", packet[:2])[0] == OP_ERROR


def send_error(bind_addr, client_addr, code, message):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((bind_addr, 0))
        sock.sendto(packet_error(code, message), client_addr)


def send_file(server_root, client_addr, filename, mode, opts, bind_addr):
    if mode not in ("octet", "netascii"):
        raise ValueError(f"unsupported mode: {mode}")
    path = safe_path(server_root, filename)
    if not os.path.isfile(path):
        raise FileNotFoundError(filename)

    blksize = 512
    reply_opts = {}
    if "blksize" in opts:
        try:
            blksize = max(512, min(int(opts["blksize"]), 1468))
            reply_opts["blksize"] = str(blksize)
        except ValueError:
            pass
    if "tsize" in opts:
        reply_opts["tsize"] = str(os.path.getsize(path))

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind((bind_addr, 0))
        sock.settimeout(3)
        if reply_opts:
            payload = b"".join(
                k.encode() + b"\0" + v.encode() + b"\0" for k, v in reply_opts.items()
            )
            oack = struct.pack("!H", OP_OACK) + payload
            sock.sendto(oack, client_addr)
            for _ in range(5):
                try:
                    ack, addr = sock.recvfrom(2048)
                except TimeoutError:
                    sock.sendto(oack, client_addr)
                    continue
                if addr != client_addr:
                    continue
                if is_tftp_error(ack):
                    return
                if is_expected_ack(ack, 0):
                    break
            else:
                return

        with open(path, "rb") as fh:
            block = 1
            while True:
                chunk = fh.read(blksize)
                pkt = struct.pack("!HH", OP_DATA, block) + chunk
                for _ in range(5):
                    sock.sendto(pkt, client_addr)
                    try:
                        ack, addr = sock.recvfrom(2048)
                    except TimeoutError:
                        continue
                    if addr != client_addr:
                        continue
                    if is_tftp_error(ack):
                        return
                    if is_expected_ack(ack, block):
                        break
                else:
                    return
                if len(chunk) < blksize:
                    return
                block = (block + 1) & 0xFFFF


def serve_rrq(server_root, client_addr, filename, mode, opts, bind_addr):
    try:
        send_file(server_root, client_addr, filename, mode, opts, bind_addr)
    except FileNotFoundError as exc:
        send_error(bind_addr, client_addr, ERR_NOT_FOUND, f"not found: {exc}")
    except PermissionError:
        send_error(bind_addr, client_addr, ERR_ACCESS, "access denied")
    except Exception as exc:
        print(f"ERR {client_addr}: {exc}", file=sys.stderr, flush=True)
        try:
            send_error(bind_addr, client_addr, ERR_ILLEGAL, str(exc))
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser(description="Minimal RFC99 netboot TFTP RRQ server")
    parser.add_argument("--root", default="/var/lib/netboot/path-b")
    parser.add_argument("--address", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=69)
    args = parser.parse_args()

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
        server.bind((args.address, args.port))
        print(f"tftp serving {args.root} on {args.address}:{args.port}", flush=True)
        while True:
            data, addr = server.recvfrom(2048)
            try:
                filename, mode, opts = parse_rrq(data)
                print(f"RRQ {addr[0]}:{addr[1]} {filename} mode={mode} opts={opts}", flush=True)
                threading.Thread(
                    target=serve_rrq,
                    args=(args.root, addr, filename, mode, opts, args.address),
                    daemon=True,
                ).start()
            except Exception as exc:
                print(f"ERR {addr}: {exc}", file=sys.stderr, flush=True)
                try:
                    server.sendto(packet_error(ERR_ILLEGAL, str(exc)), addr)
                except Exception:
                    pass


if __name__ == "__main__":
    main()
