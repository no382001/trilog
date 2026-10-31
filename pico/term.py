#!/usr/bin/env python3
# A terminal for the board with line editing and history: the line is edited
# here and sent on Enter. Ctrl-C goes to the board, Ctrl-D quits.
# usage: pico/term.py [serial port]
import atexit
import glob
import os
import readline
import sys
import termios
import threading
import time
import tty

HISTORY = os.path.expanduser("~/.trilog_pico_history")


def find_port():
    if len(sys.argv) > 1:
        return sys.argv[1]
    ports = sorted(glob.glob("/dev/ttyACM*"))
    return ports[0] if ports else None


class Board:
    def __init__(self):
        self.fd = None
        self.echo = b""
        self.lock = threading.Lock()

    def open(self):
        said = None
        while True:
            port = find_port()
            why = "no board on USB"
            if port:
                try:
                    fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
                    tty.setraw(fd)
                    termios.tcflush(fd, termios.TCIFLUSH)
                    self.fd = fd
                    return port
                except OSError as e:
                    why = f"{port}: {e.strerror}" + (
                        " (is screen still open? screen -ls)" if e.errno == 16 else "")
            if why != said:
                sys.stdout.write(f"[waiting: {why}]\r\n")
                sys.stdout.flush()
                said = why
            time.sleep(0.25)

    def send(self, data, echo=b""):
        with self.lock:
            self.echo = echo
        try:
            os.write(self.fd, data)
        except OSError:
            pass

    def read_forever(self):
        while True:
            try:
                data = os.read(self.fd, 4096)
            except OSError:
                data = b""
            if not data:
                os.close(self.fd)
                sys.stdout.write("\r\n[board gone; waiting for it]\r\n")
                sys.stdout.flush()
                port = self.open()
                sys.stdout.write(f"[back on {port}]\r\n")
                sys.stdout.flush()
                continue
            with self.lock:
                if self.echo:
                    if self.echo.startswith(data):
                        self.echo = self.echo[len(data):]
                        continue
                    if data.startswith(self.echo):
                        data = data[len(self.echo):]
                    self.echo = b""
            sys.stdout.write(data.decode(errors="replace").replace("\r\n", "\n"))
            sys.stdout.flush()


def main():
    try:
        readline.read_history_file(HISTORY)
    except OSError:
        pass
    atexit.register(readline.write_history_file, HISTORY)

    board = Board()
    port = board.open()
    print(f"[connected to {port}; Ctrl-D quits]")
    threading.Thread(target=board.read_forever, daemon=True).start()
    board.send(b"\r")
    while True:
        try:
            line = input()
        except EOFError:
            print()
            return
        except KeyboardInterrupt:
            board.send(b"\x03")
            continue
        if line.strip() in (";", "a"):
            board.send(line.strip().encode())
        else:
            board.send(line.encode() + b"\r", echo=line.encode() + b"\r\n")


if __name__ == "__main__":
    main()
