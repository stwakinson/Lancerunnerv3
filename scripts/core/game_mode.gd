class_name GameMode
extends RefCounted

# The mission type picked on the main menu (kept across scene changes).
#   INFINITE: enemies keep coming back; it goes on until the player dies.
#   CLASSIC:  a fixed force - nothing respawns, allies or enemies; destroy
#             every enemy to win.

enum Mode { INFINITE, CLASSIC }

static var current := Mode.INFINITE

static var is_classic: bool:
	get:
		return current == Mode.CLASSIC

static var title: String:
	get:
		return "CLASSIC" if is_classic else "INFINITE"
