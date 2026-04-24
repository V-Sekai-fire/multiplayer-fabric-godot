def can_build(env, platform):
    return env.get("module_multiplayer_fabric_asset_enabled", False)


def configure(env):
    pass


def get_doc_classes():
    return [
        "FabricMMOGZone",
        "FabricMMOGPeer",
    ]


def get_doc_path():
    return "doc_classes"
