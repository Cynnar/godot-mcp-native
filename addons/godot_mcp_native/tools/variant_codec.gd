@tool
extends RefCounted
## Converts Godot values into JSON-safe values for tool results.
##
## Primitives, arrays and dictionaries map to their JSON equivalents. Godot
## types that JSON can't express (Vector3, Color, Transform3D, ...) become their
## Godot text form, e.g. "Vector3(1, 2, 3)". That is the same format Godot's
## str_to_var() parses, so write tools can accept it back later.

const MAX_ITEMS := 200
const MAX_DEPTH := 6


static func to_json(value: Variant, depth: int = 0) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				return str(value)
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_ARRAY:
			if depth >= MAX_DEPTH:
				return "<array nested too deep>"
			var array_out := []
			for item in value:
				if array_out.size() >= MAX_ITEMS:
					array_out.append("... %d more items" % (value.size() - MAX_ITEMS))
					break
				array_out.append(to_json(item, depth + 1))
			return array_out
		TYPE_DICTIONARY:
			if depth >= MAX_DEPTH:
				return "<dictionary nested too deep>"
			var dict_out := {}
			for key in value:
				dict_out[str(key)] = to_json(value[key], depth + 1)
			return dict_out
		TYPE_OBJECT:
			return _describe_object(value)
		_:
			var type_id := typeof(value)
			# The packed array types are contiguous in Variant.Type.
			if type_id >= TYPE_PACKED_BYTE_ARRAY and type_id <= TYPE_PACKED_VECTOR4_ARRAY:
				if value.size() > MAX_ITEMS:
					return "<%s with %d items>" % [type_string(type_id), value.size()]
			return var_to_str(value)


static func _describe_object(obj: Variant) -> Variant:
	if not is_instance_valid(obj):
		return null
	if obj is Resource:
		var resource_info := {"_type": "Resource", "class": obj.get_class()}
		if not obj.resource_path.is_empty():
			resource_info["path"] = obj.resource_path
		return resource_info
	if obj is Node:
		return {"_type": "Node", "class": obj.get_class(), "name": str(obj.name)}
	return {"_type": "Object", "class": obj.get_class()}
