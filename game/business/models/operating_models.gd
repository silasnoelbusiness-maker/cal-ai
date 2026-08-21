class_name OperatingModels
extends RefCounted
## Picks the OperatingModel for a business and keeps one of each.
##
## Separate from OperatingModel itself so the base class never has to name its
## own subclasses — that would be a cycle, and GDScript is right to refuse it.
## One instance per model is enough because none of them hold state.

static var _cache: Dictionary = {}


static func for_business(business: BusinessInstance) -> OperatingModel:
	var definition := business.type_data() if business != null else null
	if definition == null:
		return for_model(BusinessTypeData.ServiceModel.RETAIL)
	return for_model(int(definition.service_model))


static func for_model(model_id: int) -> OperatingModel:
	if not _cache.has(model_id):
		_cache[model_id] = _make(model_id)
	return _cache[model_id]


static func _make(model_id: int) -> OperatingModel:
	match model_id:
		BusinessTypeData.ServiceModel.COUNTER_SERVICE:
			return CounterServiceModel.new()
		BusinessTypeData.ServiceModel.TABLE_SERVICE:
			return TableServiceModel.new()
		BusinessTypeData.ServiceModel.MEMBERSHIP:
			return MembershipModel.new()
		BusinessTypeData.ServiceModel.VENUE:
			return VenueModel.new()
		_:
			return OperatingModel.new()
