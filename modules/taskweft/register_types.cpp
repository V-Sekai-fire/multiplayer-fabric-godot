/**************************************************************************/
/*  register_types.cpp                                                    */
/**************************************************************************/
#include "register_types.h"

#include "core/object/class_db.h"
#include "taskweft.h"
#include "taskweft_domain.h"
#include "taskweft_state.h"

void initialize_taskweft_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<TaskweftState>();
	ClassDB::register_class<TaskweftDomain>();
	ClassDB::register_class<Taskweft>();
}

void uninitialize_taskweft_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}
