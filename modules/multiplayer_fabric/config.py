def can_build(env, platform):
    return env.get("module_sqlite_enabled", False) and env.get("module_http3_enabled", False)


def configure(env):
    pass


def get_doc_classes():
    return [
        "FabricMultiplayerPeer",
        "FabricSnapshot",
        "FabricZone",
    ]


def get_doc_path():
    return "doc_classes"
