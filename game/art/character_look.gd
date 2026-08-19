class_name CharacterLook
extends RefCounted
## What one person looks like: a handful of colours and three choices.
##
## Deliberately data rather than a scene per person. A crowd of forty is forty
## of these and one builder, so a new kind of NPC is an entry in `for_category`
## instead of a model, and the whole city can be re-dressed by editing this file.

enum Category { CIVILIAN, OFFICE, RETAIL, POLICE, PLAYER }
enum Build { SLIM, AVERAGE, HEAVY }
enum HairStyle { SHORT, CROP, BUN, CAP, BALD }

var category: Category = Category.CIVILIAN
var build: Build = Build.AVERAGE
var hair_style: HairStyle = HairStyle.SHORT

var skin: Color = Color(0.792, 0.616, 0.478)
var hair: Color = Color(0.239, 0.176, 0.137)
var top: Color = Color(0.404, 0.435, 0.502)
var accent: Color = Color(0.902, 0.788, 0.373)
var legs: Color = Color(0.267, 0.318, 0.404)
var shoes: Color = Color(0.157, 0.161, 0.176)

## Overall height in metres. The builder scales every part from this, so a
## shorter person is shorter everywhere rather than a squashed head.
var height: float = 1.78

## Skin tones, hair colours and clothing, kept as small authored sets rather
## than random channels — random RGB gives lilac skin and khaki hair.
const SKIN_TONES: Array[Color] = [
	Color(0.945, 0.804, 0.686), Color(0.878, 0.706, 0.565),
	Color(0.792, 0.616, 0.478), Color(0.647, 0.463, 0.337),
	Color(0.478, 0.333, 0.243), Color(0.361, 0.243, 0.180),
	Color(0.267, 0.180, 0.137),
]

const HAIR_TONES: Array[Color] = [
	Color(0.129, 0.106, 0.098), Color(0.239, 0.176, 0.137),
	Color(0.365, 0.251, 0.161), Color(0.545, 0.408, 0.235),
	Color(0.694, 0.573, 0.365), Color(0.451, 0.451, 0.463),
	Color(0.769, 0.769, 0.780),
]

const CASUAL_TOPS: Array[Color] = [
	Color(0.416, 0.463, 0.545), Color(0.545, 0.373, 0.345),
	Color(0.376, 0.494, 0.427), Color(0.616, 0.545, 0.404),
	Color(0.451, 0.400, 0.510), Color(0.290, 0.400, 0.451),
	Color(0.741, 0.729, 0.702), Color(0.318, 0.325, 0.361),
]

const OFFICE_TOPS: Array[Color] = [
	Color(0.184, 0.204, 0.259), Color(0.239, 0.263, 0.325),
	Color(0.278, 0.243, 0.231), Color(0.196, 0.235, 0.243),
]

const LEG_TONES: Array[Color] = [
	Color(0.220, 0.259, 0.337), Color(0.267, 0.318, 0.404),
	Color(0.239, 0.243, 0.259), Color(0.361, 0.333, 0.294),
	Color(0.169, 0.180, 0.204),
]

const SHOE_TONES: Array[Color] = [
	Color(0.129, 0.133, 0.145), Color(0.235, 0.184, 0.145),
	Color(0.788, 0.788, 0.796), Color(0.318, 0.180, 0.157),
]


## One random person of a category. The rng is passed in so a district's crowd
## is reproducible from its own seed.
static func random(rng: RandomNumberGenerator, of_category: Category = Category.CIVILIAN) -> CharacterLook:
	var look := CharacterLook.new()
	look.category = of_category
	look.skin = SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)]
	look.hair = HAIR_TONES[rng.randi_range(0, HAIR_TONES.size() - 1)]
	look.build = [Build.SLIM, Build.AVERAGE, Build.AVERAGE, Build.HEAVY][rng.randi_range(0, 3)]
	look.height = rng.randf_range(1.66, 1.88)
	look.shoes = SHOE_TONES[rng.randi_range(0, SHOE_TONES.size() - 1)]
	look.legs = LEG_TONES[rng.randi_range(0, LEG_TONES.size() - 1)]
	look.hair_style = [
		HairStyle.SHORT, HairStyle.SHORT, HairStyle.CROP, HairStyle.BUN, HairStyle.BALD
	][rng.randi_range(0, 4)]

	match of_category:
		Category.OFFICE:
			look.top = OFFICE_TOPS[rng.randi_range(0, OFFICE_TOPS.size() - 1)]
			look.accent = Color(0.749, 0.757, 0.780)
			look.legs = Color(0.196, 0.212, 0.259)
			look.shoes = Color(0.129, 0.133, 0.145)
		Category.RETAIL:
			# A uniform: everyone behind a counter in the same apron colour, so
			# staff read as staff and not as a customer who has stopped moving.
			look.top = Color(0.278, 0.435, 0.478)
			look.accent = Color(0.902, 0.902, 0.886)
			look.legs = Color(0.239, 0.243, 0.259)
		Category.POLICE:
			look.top = Color(0.129, 0.169, 0.239)
			look.accent = Color(0.914, 0.792, 0.290)
			look.legs = Color(0.106, 0.129, 0.180)
			look.shoes = Color(0.098, 0.102, 0.114)
			look.hair_style = HairStyle.CAP
		_:
			look.top = CASUAL_TOPS[rng.randi_range(0, CASUAL_TOPS.size() - 1)]
			look.accent = look.top.lightened(0.22)
	return look


## The one authored default: who the player is until a creator exists.
static func player_default() -> CharacterLook:
	var look := CharacterLook.new()
	look.category = Category.PLAYER
	look.build = Build.AVERAGE
	look.height = 1.80
	look.hair_style = HairStyle.CROP
	look.skin = Color(0.831, 0.663, 0.510)
	look.hair = Color(0.196, 0.153, 0.129)
	look.top = Color(0.220, 0.404, 0.639)
	look.accent = Color(0.941, 0.804, 0.325)
	look.legs = Color(0.216, 0.235, 0.290)
	look.shoes = Color(0.878, 0.882, 0.894)
	return look


## Shoulder width multiplier for the build.
func shoulder_scale() -> float:
	match build:
		Build.SLIM:
			return 0.90
		Build.HEAVY:
			return 1.16
		_:
			return 1.0


## Waist/hip multiplier, so a heavy build is not only broader at the shoulder.
func waist_scale() -> float:
	match build:
		Build.SLIM:
			return 0.88
		Build.HEAVY:
			return 1.22
		_:
			return 1.0


func duplicate_look() -> CharacterLook:
	var copy := CharacterLook.new()
	copy.category = category
	copy.build = build
	copy.hair_style = hair_style
	copy.skin = skin
	copy.hair = hair
	copy.top = top
	copy.accent = accent
	copy.legs = legs
	copy.shoes = shoes
	copy.height = height
	return copy
