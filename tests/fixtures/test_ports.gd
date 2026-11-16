class_name TestPorts
extends RefCounted
## Hands out a UDP port no other test in this run has been given.
##
## Lives outside tests/unit so GUT does not scan it for tests.
##
## **Why this exists.** Tests that bind a socket used to pick a port at random
## out of a few hundred and hope. Hope is not a strategy for about seven draws:
## roughly one run in twenty, two tests drew the same number while the first
## was still holding it, and the second failed to bind. That produced a red run
## that nobody could reproduce — three failed asserts in one test, gone on the
## next run — and it sat in docs/testing.md as unexplained for a day before the
## engine error underneath it ("Couldn't create an ENet host") named the cause.
##
## Counting is enough. A port is never handed out twice in a process, and the
## previous process's ports went back to the operating system when it exited.
##
## **No probe bind.** Checking a port by binding it would push an engine error
## on the attempt that failed, and GUT fails a test for an engine error it was
## not told to expect — so the check would cause the thing it was meant to
## prevent. Uniqueness within the run is what the fault needed.
##
## Each caller takes its own range so two scripts cannot meet in the middle.
## Ranges are in the IANA dynamic range and avoid the game's own default of
## 42420, which a developer may well have a copy of the game sitting on.


## Where each caller's run of ports begins. Spaced far enough apart that a long
## script cannot walk into the next one.
const LOBBY_BASE: int = 43100
const LAUNCH_BASE: int = 43600
const TRANSPORT_BASE: int = 44800


static var _taken: Dictionary[int, int] = {}


## The next unused port at or after `base`.
static func next(base: int) -> int:
	var offset: int = _taken.get(base, 0)
	_taken[base] = offset + 1
	return base + offset
