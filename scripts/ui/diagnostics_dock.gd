extends RefCounted
## Find free HUD space; suspend diagnostics behind full-screen menus instead
## of covering their controls. No production cost while F7 is disabled.
static func obstacles(node: Node, excluded: Node, canvas := false) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if node==excluded or node is SubViewport: return result
	if node is CanvasLayer:
		if not node.visible: return result
		canvas=true
	if node is Control and canvas:
		if not node.is_visible_in_tree(): return result
		var rect: Rect2 = node.get_global_rect()
		if rect.size.x>8 and rect.size.y>8:
			result.append(rect.grow(8))
			return result
	for child in node.get_children(): result.append_array(obstacles(child,excluded,canvas))
	return result

static func place(panel: Control,excluded: Node,root: Node) -> void:
	var occupied := obstacles(root,excluded)
	var viewport := panel.get_viewport_rect().size
	var best := Vector2(-1,-1)
	var score := INF
	for y in range(170,int(viewport.y-panel.size.y-10),20):
		for x in range(16,int(viewport.x-panel.size.x-10),20):
			var rect := Rect2(Vector2(x,y),panel.size)
			var clear := true
			for other in occupied:
				if rect.intersects(other): clear=false; break
			var rank := rect.position.distance_squared_to(Vector2(420,260))
			if clear and rank<score: best=rect.position; score=rank
	panel.visible=best.x>=0
	if panel.visible: panel.position=best
