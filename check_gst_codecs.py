#!/usr/bin/env python3

import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst

Gst.init(None)

def list_codecs():
    registry = Gst.Registry.get()
    plugins = registry.get_plugin_list()
    for plugin in plugins:
        for feature in registry.get_feature_list_by_plugin(plugin.get_name()):
            if isinstance(feature, Gst.ElementFactory):
                try:
                    # Try get_klass() first, fallback to get_metadata('klass')
                    if hasattr(feature, 'get_klass'):
                        klass = feature.get_klass()
                    else:
                        klass = feature.get_metadata('klass')
                    if klass:
                        klass = klass.lower()
                        if 'decoder' in klass or 'encoder' in klass:
                            plugin_obj = feature.get_plugin()
                            plugin_path = plugin_obj.get_filename() if plugin_obj else "unknown"
                            print(f"{feature.get_name():20} - {klass:25} - {plugin_path}")
                except Exception as e:
                    print(f"Error with feature {feature.get_name()}: {e}")
            else:
                # Optionally print info about non-ElementFactory features
                pass

list_codecs()
