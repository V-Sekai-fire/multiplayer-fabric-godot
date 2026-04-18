#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "aioquic>=1.0.0",
#   "prompt_toolkit>=3.0.52,<4",
#   "rich>=14.3.3,<15",
# ]
# ///
"""
zone_console.py — lofi zone operator console

Connects to a Multiplayer Fabric zone server over WebTransport and lets you
inspect entity state and inject commands from the terminal.

Usage:
    uv run zone_console.py [host] [port]
    uv run zone_console.py                  # defaults: localhost 7000
"""

from __future__ import annotations

import asyncio
import json
import struct
import sys

import aioquic.asyncio as quic_asyncio
from aioquic.quic.configuration import QuicConfiguration
from prompt_toolkit import PromptSession
from prompt_toolkit.completion import WordCompleter
from prompt_toolkit.history import InMemoryHistory
from prompt_toolkit.patch_stdout import patch_stdout
from prompt_toolkit.styles import Style
from rich.console import Console
from rich.table import Table

console = Console()

COMMANDS = [
    "help",
    "status",
    "entities",
    "kick",
    "tombstone",
    "rip",
    "bloom",
    "quit",
    "exit",
]

STYLE = Style.from_dict({
    "prompt": "ansicyan bold",
    "": "ansiwhite",
})

BANNER = """
[bold cyan]Multiplayer Fabric Zone Console[/bold cyan]
[dim]Type [bold]help[/bold] for available commands.  Ctrl-D or [bold]exit[/bold] to quit.[/dim]
"""


# ── WebTransport stub ─────────────────────────────────────────────────────────
# Full WT datagram support requires a running zone server.  The client below
# degrades gracefully to offline mode when no server is reachable, so the TUI
# is usable for development before the server is up.


class ZoneConnection:
    """Thin async wrapper around a WebTransport zone link."""

    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self._connected = False
        self._send_queue: asyncio.Queue[dict[str, object]] = asyncio.Queue()
        self._recv_queue: asyncio.Queue[dict[str, object]] = asyncio.Queue()

    @property
    def connected(self) -> bool:
        return self._connected

    async def connect(self) -> bool:
        config = QuicConfiguration(is_client=True, alpn_protocols=["h3"])
        config.verify_mode = False  # self-signed certs on dev zones
        try:
            async with quic_asyncio.connect(self.host, self.port, configuration=config) as quic_conn:
                self._connected = True
                console.print(f"[green]Connected to {self.host}:{self.port}[/green]")
                await self._run(quic_conn)
        except Exception as exc:
            console.print(f"[yellow]Offline mode — could not reach {self.host}:{self.port}: {exc}[/yellow]")
            self._connected = False
        return self._connected

    async def _run(self, quic_conn):
        while True:
            try:
                msg = await asyncio.wait_for(self._send_queue.get(), timeout=1.0)
                # CH_MIGRATION = channel 1, reliable
                # Frame format matches wtd: flag byte (channel<<1 | reliable) + payload
                flag = (1 << 1) | 1
                payload = json.dumps(msg).encode()
                frame = bytes([flag]) + struct.pack(">H", len(payload)) + payload
                quic_conn.send_datagram_frame(frame)
                await asyncio.sleep(0)
            except asyncio.TimeoutError:
                pass
            except Exception:
                break

    async def send(self, msg: dict[str, object]) -> None:
        if self._connected:
            await self._send_queue.put(msg)

    async def recv(self) -> dict[str, object] | None:
        try:
            return self._recv_queue.get_nowait()
        except asyncio.QueueEmpty:
            return None


# ── command handlers ───────────────────────────────────────────────────────��──


async def cmd_help(_args, _conn) -> None:
    table = Table(show_header=False, box=None, padding=(0, 2))
    rows = [
        ("help", "show this message"),
        ("status", "zone ID, entity count, neighbor links"),
        ("entities [limit]", "list live entities (default 20)"),
        ("kick <entity_id>", "force-migrate entity out of zone"),
        ("tombstone <asset_hash>", "blacklist UGC asset; despawn instances"),
        ("rip <x> <z> <intensity>", "inject rip current into flow field"),
        ("bloom <x> <z>", "trigger jellyfish bloom event"),
        ("exit / quit", "disconnect and exit"),
    ]
    for cmd, desc in rows:
        table.add_row(f"[bold cyan]{cmd}[/bold cyan]", f"[dim]{desc}[/dim]")
    console.print(table)


async def cmd_status(_args, conn: ZoneConnection) -> None:
    if not conn.connected:
        console.print("[yellow]offline — not connected to zone[/yellow]")
        return
    await conn.send({"op": "status"})
    await asyncio.sleep(0.1)
    resp = await conn.recv()
    if resp:
        _print_status(resp)
    else:
        console.print("[dim]no response[/dim]")


def _print_status(data: dict[str, object]) -> None:
    table = Table(show_header=False, box=None, padding=(0, 2))
    for k, v in data.items():
        table.add_row(f"[cyan]{k}[/cyan]", str(v))
    console.print(table)


async def cmd_entities(args, conn: ZoneConnection) -> None:
    limit = int(args[0]) if args else 20
    if not conn.connected:
        console.print("[yellow]offline[/yellow]")
        return
    await conn.send({"op": "entities", "limit": limit})
    await asyncio.sleep(0.1)
    resp = await conn.recv()
    if not resp:
        console.print("[dim]no response[/dim]")
        return
    table = Table("id", "asset", "x", "z", "phase", box=None)
    entities = resp.get("entities", [])
    assert isinstance(entities, list)
    for e in entities:
        table.add_row(
            str(e.get("id", "?")),
            e.get("asset", "?")[:12],
            f"{e.get('x', 0):.2f}",
            f"{e.get('z', 0):.2f}",
            f"{e.get('phase', 0):.2f}",
        )
    console.print(table)


async def cmd_kick(args, conn: ZoneConnection) -> None:
    if not args:
        console.print("[red]usage: kick <entity_id>[/red]")
        return
    await conn.send({"op": "kick", "entity_id": args[0]})
    console.print(f"[green]sent kick for entity {args[0]}[/green]")


async def cmd_tombstone(args, conn: ZoneConnection) -> None:
    if not args:
        console.print("[red]usage: tombstone <asset_hash>[/red]")
        return
    await conn.send({"op": "tombstone", "hash": args[0]})
    console.print(f"[green]tombstoned asset {args[0]}[/green]")


async def cmd_rip(args, conn: ZoneConnection) -> None:
    if len(args) < 3:
        console.print("[red]usage: rip <x> <z> <intensity>[/red]")
        return
    await conn.send({
        "op": "rip",
        "x": float(args[0]),
        "z": float(args[1]),
        "intensity": float(args[2]),
    })
    console.print(f"[green]rip current injected at ({args[0]}, {args[1]})[/green]")


async def cmd_bloom(args, conn: ZoneConnection) -> None:
    if len(args) < 2:
        console.print("[red]usage: bloom <x> <z>[/red]")
        return
    await conn.send({"op": "bloom", "x": float(args[0]), "z": float(args[1])})
    console.print(f"[green]bloom triggered at ({args[0]}, {args[1]})[/green]")


DISPATCH = {
    "help": cmd_help,
    "status": cmd_status,
    "entities": cmd_entities,
    "kick": cmd_kick,
    "tombstone": cmd_tombstone,
    "rip": cmd_rip,
    "bloom": cmd_bloom,
}


# ── main REPL ─────────────────────────────────────────────────────────────────


async def repl(conn: ZoneConnection) -> None:
    completer = WordCompleter(COMMANDS, ignore_case=True)
    session: PromptSession = PromptSession(
        history=InMemoryHistory(),
        completer=completer,
        style=STYLE,
    )
    console.print(BANNER)
    status_str = (
        f"[green]{conn.host}:{conn.port}[/green]"
        if conn.connected
        else f"[yellow]offline ({conn.host}:{conn.port})[/yellow]"
    )
    console.print(f"Zone: {status_str}\n")

    with patch_stdout():
        while True:
            try:
                line = await session.prompt_async("zone> ")
            except (EOFError, KeyboardInterrupt):
                console.print("[dim]bye[/dim]")
                break

            line = line.strip()
            if not line:
                continue
            parts = line.split()
            cmd, args = parts[0].lower(), parts[1:]

            if cmd in ("exit", "quit"):
                console.print("[dim]bye[/dim]")
                break

            handler = DISPATCH.get(cmd)
            if handler:
                try:
                    await handler(args, conn)
                except Exception as exc:
                    console.print(f"[red]error: {exc}[/red]")
            else:
                console.print(f"[red]unknown command:[/red] {cmd}  [dim](try [bold]help[/bold])[/dim]")


async def main(host: str, port: int) -> None:
    conn = ZoneConnection(host, port)
    connect_task = asyncio.create_task(conn.connect())
    # Give the connection 2 s before dropping into the REPL in offline mode
    await asyncio.wait([connect_task], timeout=2.0)
    await repl(conn)
    connect_task.cancel()


if __name__ == "__main__":
    host = sys.argv[1] if len(sys.argv) > 1 else "localhost"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 7000
    asyncio.run(main(host, port))
