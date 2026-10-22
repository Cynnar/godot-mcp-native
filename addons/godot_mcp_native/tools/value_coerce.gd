@tool
extends RefCounted
## Shared value conversion for tools that set properties (nodes, resources,
## project settings). Turns JSON-friendly input into the Variant type a
## property expects.

## Converts value for a property of obj. Returns {"value": ...} or {"error": ...}.
static func property(obj: Object, prop_name: String, value: Variant) -> Dictionary:
	var expected := -1
	for prop_info in obj.get_property_list():
		if prop_info["name"] == prop_name:
			expected = int(prop_info["type"])
			break
	if expected < 0:
		var label := "'%s' (%s)" % [obj.name, obj.get_class()] if obj is Node else obj.get_class()
		return {"error": "%s has no property '%s'. Use the matching get_*_properties tool to see valid names." % [label, prop_name]}
	return to_type(expected, value)


## Converts value to the Variant type expected (a TYPE_* constant).
static func to_type(expected: int, value: Variant) -> Dictionary:
	match expected:
		TYPE_STRING:
			return {"value": str(value)}
		TYPE_STRING_NAME:
			return {"value": StringName(str(value))}
		TYPE_NODE_PATH:
			return {"value": NodePath(str(value))}
		TYPE_BOOL:
			if typeof(value) == TYPE_BOOL:
				return {"value": value}
		TYPE_INT:
			if typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
				return {"value": int(value)}
		TYPE_FLOAT:
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				return {"value": float(value)}
		TYPE_VECTOR2:
			if value is Array and value.size() == 2:
				return {"value": Vector2(value[0], value[1])}
		TYPE_VECTOR3:
			if value is Array and value.size() == 3:
				return {"value": Vector3(value[0], value[1], value[2])}
		TYPE_COLOR:
			if value is Array and value.size() == 3:
				return {"value": Color(value[0], value[1], value[2])}
			if value is Array and value.size() == 4:
				return {"value": Color(value[0], value[1], value[2], value[3])}
		TYPE_OBJECT:
			if value == null:
				return {"value": null}
			if typeof(value) == TYPE_STRING and str(value).begins_with("res://"):
				var resource := load(str(value))
				if resource == null:
					return {"error": "Could not load resource '%s'." % str(value)}
				return {"value": resource}

	# Everything else arrives in Godot text form, e.g. "Rect2(0, 0, 10, 10)".
	if typeof(value) == TYPE_STRING:
		var parsed = str_to_var(value)
		if parsed == null and str(value).strip_edges() != "null":
			return {"error": "Could not parse '%s' as %s. Use Godot text form such as Vector2(1, 2) or Color(1, 0, 0, 1)." % [value, type_string(expected)]}
		return {"value": parsed}
	return {"value": value}
