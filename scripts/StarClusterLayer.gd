extends Node2D
class_name StarClusterLayer

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var stars: Array[Dictionary] = []

func build() -> void:
    z_index = -20
    _rng.seed = 202650
    stars.clear()

    # Clustered distribution + intentional voids.
    var clusters: Array[Dictionary] = [
        {"c":Vector2(1650,470),"r":Vector2(1120,430),"n":1250},
        {"c":Vector2(720,1220),"r":Vector2(650,440),"n":720},
        {"c":Vector2(2510,1180),"r":Vector2(820,480),"n":850},
        {"c":Vector2(360,470),"r":Vector2(430,320),"n":330},
        {"c":Vector2(1850,1150),"r":Vector2(720,260),"n":260}
    ]

    for cl in clusters:
        var c: Vector2 = cl["c"]
        var r: Vector2 = cl["r"]
        var n: int = int(cl["n"])
        for i in range(n):
            var ang: float = _rng.randf_range(0.0,TAU)
            var rr: float = pow(_rng.randf(),0.62)
            var p: Vector2 = c+Vector2(cos(ang)*r.x*rr,sin(ang)*r.y*rr)

            # Carve a couple of star-poor voids.
            if p.distance_to(Vector2(1420,870)) < 260.0:
                continue
            if p.distance_to(Vector2(2780,390)) < 230.0:
                continue

            stars.append({
                "p":p,
                "r":_rng.randf_range(.42,1.65),
                "a":_rng.randf_range(.18,.88),
                "warm":_rng.randf()>.91
            })

func _draw() -> void:
    for s in stars:
        var p: Vector2 = s["p"]
        var r: float = float(s["r"])
        var a: float = float(s["a"])
        var c: Color = Color(.64,.84,1.0,a)
        if bool(s["warm"]):
            c=Color(1.0,.82,.50,a)
        draw_circle(p,r*3.2,Color(c.r,c.g,c.b,a*.055))
        draw_circle(p,r,c)
