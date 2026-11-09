extends Node2D
var ppm := .15
var dimensions := Vector2(1040,704)

func _draw() -> void:
	var feet := 50.0
	for candidate in [50,100,200,500,1000,2000,2640,5280,10560]:
		if float(candidate)/3.28084*ppm<=130: feet=float(candidate)
	var width := feet/3.28084*ppm
	var origin := Vector2(16,dimensions.y-20)
	var label := "%d ft"%roundi(feet) if feet<2640 else ("½ mi" if feet==2640 else "%d mi"%roundi(feet/5280))
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(origin-Vector2(7,25),Vector2(maxf(65,width+14),38)),Color(.94,.92,.85,.88))
	for i in 4:
		draw_rect(Rect2(origin+Vector2(width*i/4,0),Vector2(width/4,5)),Color("47625b") if i%2==0 else Color("dedcc7"))
	draw_string(font,origin+Vector2(0,-5),label,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("38534e"))
	var north := Vector2(dimensions.x-25,26)
	draw_circle(north,14,Color(.94,.92,.85,.85))
	draw_string(font,north+Vector2(-4,-17),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("38534e"))
	draw_colored_polygon(PackedVector2Array([north+Vector2(0,-9),north+Vector2(5,7),north,north+Vector2(-5,7)]),Color("47625b"))
