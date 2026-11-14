extends Resource
## Locations follow named roads in the loaded archive, surviving road edits.
@export var event_id:=""
@export var title:="Street Event"
@export var district:="Morrow Coast"
@export var start_road:=""
@export var start_piece:=0
@export_range(.05,.95) var start_fraction:=.2
@export var finish_road:=""
@export var finish_piece:=0
@export_range(.05,.95) var finish_fraction:=.8
@export var time_limit_seconds:=600.0
