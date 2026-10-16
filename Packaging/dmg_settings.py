from pathlib import Path

application = Path(defines["app"]).resolve()
assets = Path(defines["assets"]).resolve()
format = "UDZO"
filesystem = "HFS+"
files = [(str(application), application.name)]
symlinks = {"Applications": "/Applications"}
icon = str(assets.parent / "Resources" / "AppIcon.icns")
background = str(assets / "background.tiff")
icon_locations = {application.name: (190, 232), "Applications": (530, 232)}
window_rect = ((160, 160), (720, 480))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
include_icon_view_settings = True
icon_size = 112
text_size = 13
label_pos = "bottom"
arrange_by = None
scroll_position = (0, 0)
