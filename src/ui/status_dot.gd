class_name StatusDot
extends RefCounted
## The small square the rankings use for a player's ready status
## (`ranking_row.tscn`, `%ReadyDot`: a 6 x 6 flat square tinted from Palette),
## as a texture, so a Button can carry one as its icon.
##
## Used for unread messages (decisions.md D192): the MESSAGES tab and each name
## in its player list. Grey (Palette.TEXT_FAINT, the rankings' away colour) for
## nothing unread, yellow (Palette.UNREAD) for something unread.
##
## A texture rather than a Panel beside the button, because a Button is not a
## container and its icon is the one place it lays out something next to its
## text by itself.


## The ready dot's size, in pixels.
const SIZE: int = 6

static var _made: Dictionary[Color, ImageTexture] = {}


## A SIZE x SIZE square of `colour`. Made once per colour and shared.
static func texture(colour: Color) -> ImageTexture:
	if not _made.has(colour):
		var image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		image.fill(colour)
		_made[colour] = ImageTexture.create_from_image(image)
	return _made[colour]


## The unread dot: yellow when `unread`, grey when not.
static func unread(is_unread: bool) -> ImageTexture:
	if is_unread:
		return texture(Palette.UNREAD)
	return texture(Palette.TEXT_FAINT)
