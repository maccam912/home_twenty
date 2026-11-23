extends RefCounted

# World coordinates are metres. County Q follows the north-south section line.
const ROAD_NORTH_Z := -1820.0
const ROAD_SOUTH_Z := 200.0
const HOME_Z := 38.0
const BECK_Z := -1572.0
const COOP_Z := -880.0
const HOME_HOUSE := Vector3(-96.0, 0.0, HOME_Z)
const BECK_HOUSE := Vector3(124.5, 0.0, BECK_Z + 13.4)
const HOME_PORCH := Vector2(-89.0, HOME_Z)
const BECK_PORCH := Vector2(122.0, BECK_Z + 8.0)
const HOME_PARK := Vector2(-76.0, HOME_Z)
const BECK_PARK := Vector2(124.0, BECK_Z)
const BECK_MAILBOX := Vector3(5.8, 0.0, BECK_Z + 4.9)
const TANK := Vector3(125.0, 0.0, BECK_Z - 6.0)
# Ground positions of the tank centre and the mailbox timber under its overhanging door.
const SNOW_CONTACTS := Vector4(TANK.x, TANK.z, BECK_MAILBOX.x + .05, BECK_MAILBOX.z - .13)
const FIRST_SLICE := 4
const LAST_SLICE := 117
const FULL_LANE := LAST_SLICE - FIRST_SLICE + 1

# Driveable strips share edges with the county road. Both farmyards widen for a turn.
const SURFACES := [
	[Vector2(-4.3, ROAD_NORTH_Z), Vector2(4.3, ROAD_SOUTH_Z)],
	[Vector2(4.3, BECK_Z - 2.7), Vector2(118.0, BECK_Z + 2.7)],
	[Vector2(118.0, BECK_Z - 12.5), Vector2(138.0, BECK_Z + 6.0)],
	[Vector2(-78.0, HOME_Z - 2.8), Vector2(-4.3, HOME_Z + 2.8)],
	[Vector2(-91.0, HOME_Z - 8.5), Vector2(-78.0, HOME_Z + 8.5)],
]
