class_name SafeArea
extends RefCounted
## Converts the device's safe area into viewport-space margins.
##
## The Pixel 9 has a camera cutout at the top and a gesture-navigation bar at
## the bottom; anything drawn at the literal screen edge gets clipped or eaten
## by a system gesture. The safe area is reported in *screen* pixels while the
## game draws in *viewport* units (a 1280x720 canvas stretched to fit), so the
## two have to be reconciled rather than used interchangeably.
##
## On desktop and web the safe area equals the screen, so this returns zeros
## and costs nothing.


## Returns (left, top, right, bottom) insets in viewport units.
static func margins(viewport_size: Vector2) -> Vector4:
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0:
		return Vector4.ZERO

	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO

	var scale := Vector2(viewport_size.x / float(screen.x), viewport_size.y / float(screen.y))
	return Vector4(
		maxf(safe.position.x, 0) * scale.x,
		maxf(safe.position.y, 0) * scale.y,
		maxf(screen.x - safe.end.x, 0) * scale.x,
		maxf(screen.y - safe.end.y, 0) * scale.y
	)
