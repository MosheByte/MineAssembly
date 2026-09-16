# Playing with Minecraft Java Edition

MineAssembly can host the world you're playing in so that real Minecraft Java Edition clients can join it. Your friends use the official launcher and the normal Multiplayer screen, the same way they'd join any server. They walk around your world, break and place blocks, and chat with you, and you see them in your world with their names over their heads.

It's meant for a LAN or a few friends you trust. Read [Limits](#limits) before you open it to anyone.

## Hosting a world

Load or create a world first, press `Esc` and click **Open to Java Edition** in the pause menu. The button shows the port it will use: 25565 (the default port for Java Edition servers) the first time, after that the last port you hosted on. Once the world is open the button turns into **Stop hosting (port N)** and the line under it counts the Java players that are on.

You can do the same from chat. Open it with `T` or `/` and type:

```
/host
```

That opens the world on port 25565. You'll see `open to java edition 26.1 players on port 25565` in chat. To use a different port (anything from 1 to 65535):

```
/host 25570
```

If the world is already open, `/host` just tells you which port it's on.

You can also host from the command line. `--host PORT` opens every world you load as soon as its spawn area is ready, and together with `--world` it skips the title screen:

```bat
MineAssembly.exe --world myworld --host 25565
```

The server stays up while the game is paused, so pausing doesn't kick anyone. It closes when you click Stop hosting, type `/unhost`, use Save and Quit to Title or close the game, and every Java player gets disconnected at that point.

### Host commands

| Command | What it does |
|---|---|
| `/host [port]` | Open the world, on 25565 if you leave the port out |
| `/unhost` | Close it again. Everyone on it gets "Server closed" |
| `/who` | List the Java players that are on, and how many |
| `/kick <name> [reason]` | Disconnect one player. They see the reason (or "Kicked by the host") on their disconnect screen. Names aren't case sensitive |

A kicked player can join again right away, there's no ban list. `/help` lists these with the other commands.

### The Windows firewall

The first time MineAssembly starts listening, Windows Defender Firewall will probably ask whether to allow it on your networks. Allow it on private networks if you want people on your LAN to get in. If you clicked Cancel earlier, find MineAssembly under "Allow an app through Windows Firewall" in the Control Panel and tick Private.

### Your IP address

Your friends need your computer's local IP address. Run `ipconfig` in a command prompt and look for the IPv4 Address of your network adapter, something like `192.168.1.20`. If the Java client runs on the same PC as MineAssembly, `localhost` works too.

## Joining from Java Edition

On the friend's computer, in the official Minecraft launcher:

1. Open Installations, click New installation, pick version 26.1 (release) and create it. The server only speaks 26.1, so other versions can't join.
2. Play that installation.
3. Go to Multiplayer, then Add Server.
4. For the server address, type the host's IP. If the host used a port other than 25565, add it after a colon, like `192.168.1.20:25570`.
5. Click Done, wait for the server to show up in the list, and join.

The server list entry says "MineAssembly - x86-64 asm" and shows how many players are on, out of 16.

## What works

- Java players spawn next to you in creative mode and can walk and fly around your world.
- They break blocks instantly (it's creative) and place blocks from their hotbar. You see their changes right away, and they see yours, including blocks other Java players change.
- Chat works both ways. Your messages show up for them as `<MineAsm> ...`, theirs show up in your chat as `<name> ...`, and everyone sees join and leave messages.
- You see Java players as figures with their names above them (visible through walls, like in Java Edition). They see you as a player called MineAsm and they see each other.
- The time of day is shared, so day and night match on every screen.
- Java players can type `/help` and `/list`. `/list` shows who's online.

## Limits

- Offline mode. The server doesn't check names with Mojang or Microsoft and the connection isn't encrypted. Anyone who can reach the port can join under any name that isn't already taken. Only use it on your LAN or with people you trust, and don't forward the port on your router unless you understand that.
- Version 26.1 only (protocol 775). Any other version gets "this server runs Minecraft 26.1, please join with that version".
- One world, the one you have open. There's only the overworld, so Java players can't go to other dimensions.
- Java players are always in creative. There's no survival for them: no health, hunger or damage.
- MineAssembly worlds are 128 blocks tall, from y 0 to 127. Java Edition's world goes from y −64 to 319, so Java players see solid stone below y 0 (bedrock at the very bottom, y −64) and empty air above 127. Building outside 0 to 127 doesn't stick: the block pops back to what MineAssembly has there.
- Blocks are matched to the closest equivalent on each side. MineAssembly's own blocks show up for Java players as the nearest Java block, and a Java block that MineAssembly doesn't have becomes the closest MineAssembly block when it's placed. Items that aren't blocks can't be placed.
- Java players only see terrain, blocks and other players. Mobs, dropped items, TNT, falling sand and weather aren't sent to them.
- The world only loads around you, the host. Java players get chunks within their own render distance (capped at 16 chunks), but only chunks you have loaded, so if they wander far from you they reach the edge of the world. Raising your render distance gives them more room.
- Dropping items and the off hand don't do anything.
- Players get the default skins, since offline mode has no skin data.
- Up to 16 connections at a time. Player names must be 1 to 16 characters with no spaces.

## Troubleshooting

If the port can't be opened you get a red line like `Port 25565 is already in use. Try /host 25567`, in chat and under the pause menu button. Something else is listening on it, usually another server (a Java server holding it shows up as `is in use or reserved`). MineAssembly checks the next few ports and suggests the first free one, so type that `/host` command and tell your friends to add the port to the address, like `:25567`. If none of them is free the message says to try another port.

If your friend's server list shows the server as unreachable or the connection times out:

- Check that the firewall allows MineAssembly (see [The Windows firewall](#the-windows-firewall)).
- Make sure both computers are on the same network and that they typed the IP from `ipconfig`, with the port if it isn't 25565.
- Make sure the world is actually open: the pause menu button should say Stop hosting, and `/host` again says `already open on port ...`.

If the server shows up but joining fails, the disconnect screen says why: the wrong version, a name that's already playing (pick a different one), an invalid name, or "server is full".

A player whose game stops answering for 30 seconds gets disconnected with "Timed out".

MineAssembly writes what the server does to `mineassembly.log` next to the exe. Look for lines starting with `net:`. `net: listening on port ...` means hosting started, `net: connection from ...` means a client reached you, and `net: ... has protocol ..., we speak 775` means the client is on another version.

---

*MineAssembly is an original Minecraft-like game. It is not affiliated with or endorsed by Mojang or Microsoft.*
