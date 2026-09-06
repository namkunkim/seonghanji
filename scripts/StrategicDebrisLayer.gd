extends Node2D
class_name StrategicDebrisLayer

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var items: Array[Dictionary] = []

func build() -> void:
    z_index = -5
    _rng.seed = 991733
    items.clear()

    _spawn_zone(Vector2(2350,1090),Vector2(520,230),430)
    _spawn_zone(Vector2(1450,825),Vector2(980,150),330)
    _spawn_zone(Vector2(2250,1320),Vector2(900,140),220)

func _spawn_zone(center: Vector2, radius: Vector2, count: int) -> void:
    for i in range(count):
        var ang: float = _rng.randf_range(0.0,TAU)
        var rr: float = sqrt(_rng.randf())
        items.append({
            "p":center+Vector2(cos(ang)*radius.x*rr,sin(ang)*radius.y*rr),
            "r":_rng.randf_range(.8,4.8),
            "a":_rng.randf_range(.12,.52)
        })

func _draw() -> void:
    for item in items:
        var p: Vector2 = item["p"]
        var r: float = float(item["r"])
        var a: float = float(item["a"])
        draw_circle(p,r,Color(.35,.40,.47,a))
