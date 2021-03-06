/******************************************************************************
 * Copyright (C) 2011-2013  Michael Hofmann <mh21@mh21.de>                    *
 *                                                                            *
 * This program is free software; you can redistribute it and/or modify       *
 * it under the terms of the GNU General Public License as published by       *
 * the Free Software Foundation; either version 3 of the License, or          *
 * (at your option) any later version.                                        *
 *                                                                            *
 * This program is distributed in the hope that it will be useful,            *
 * but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 * GNU General Public License for more details.                               *
 *                                                                            *
 * You should have received a copy of the GNU General Public License along    *
 * with this program; if not, write to the Free Software Foundation, Inc.,    *
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.                *
 ******************************************************************************/

public class Preferences : Object {
    // always allocated
    private SettingsCache settingscache;
    private Settings prefsettings;

    // only when dialog is visible
    private Gtk.Dialog preferences;
    private Gtk.Builder builder;

    // helper
    private unowned Gtk.ComboBox colorschemes;
    private bool colorschemeignoresignals;

    public ColorMapper colormapper { get; construct; }

    public signal void advancedpreferences_show();
    public signal void menupreferences_show();
    public signal void indicatorpreferences_show();

    delegate void ColorForeachFunc(Settings settings, string key,
            Object? widget, string name);

    public Preferences(ColorMapper colormapper) {
        Object(colormapper: colormapper);
    }

    construct {
        this.settingscache = new SettingsCache();
        this.prefsettings = this.settingscache.generalsettings();

        this.colorgsettings_foreach((settings, key, widget, name) => {
            settings.changed[key].connect(this.update_activecolorscheme);
        });
    }

    public void show() {
        if (this.preferences != null) {
            this.preferences.present();
            return;
        }

        this.preferences = Utils.get_ui("preferencesdialog", this,
                {"widthadjustment", "speedadjustment", "schemestore"},
                out this.builder) as Gtk.Dialog;
        return_if_fail(this.preferences != null);

        this.colorschemes = this.builder.get_object("colorschemes") as Gtk.ComboBox;

        var schemestore = this.builder.get_object("schemestore") as Gtk.ListStore;
        foreach (var colorscheme in ColorMapper.colorschemes) {
            schemestore.insert_with_values(null, -1,
                    0, ColorMapper.schemelabel(colorscheme),
                    1, colorscheme);
        }
        // TRANSLATORS: custom color scheme
        schemestore.insert_with_values(null, -1, 0, _("Custom"), 1, "custom");

        foreach (var graphid in this.prefsettings.get_strv("graphs")) {
            if (!(graphid in SettingsCache.presetgraphids))
                continue;
            var graphsettings = this.settingscache.graphsettings(graphid);
            graphsettings.bind("enabled",
                    this.builder.get_object(@"$(graphid)-enabled"), "active",
                    SettingsBindFlags.DEFAULT);
        }

        this.colorgsettings_foreach((settings, key, widget, name) => {
            PGLib.settings_bind_with_mapping(settings, key,
                    widget, "rgba",
                    SettingsBindFlags.DEFAULT,
                    Utils.get_settings_rgba,
                    (PGLib.SettingsBindSetMapping)Utils.set_settings_rgba,
                    null, () => {});
        });

        // TODO: rgba, alpha need settings conversion
        this.prefsettings.bind("width",
                this.builder.get_object("width"), "value",
                SettingsBindFlags.DEFAULT);
        this.prefsettings.bind("speed",
                this.builder.get_object("speed"), "value",
                SettingsBindFlags.DEFAULT);
        this.prefsettings.bind("autostart",
                this.builder.get_object("autostart"), "active",
                SettingsBindFlags.DEFAULT);

        this.update_activecolorscheme();

        this.preferences.show_all();
    }

    [CCode (instance_pos = -1)]
    public void on_preferencesdialog_destroy(Gtk.Widget source) {
        this.preferences = null;
        this.builder = null;
    }

    [CCode (instance_pos = -1)]
    public void on_preferencesdialog_response(Gtk.Dialog source, int response) {
        switch (response) {
        case 0: // close
            source.destroy();
            return;
        case 1:
            this.advancedpreferences_show();
            return;
        case 2:
            this.menupreferences_show();
            return;
        case 3:
            this.indicatorpreferences_show();
            return;
        }
    }

    [CCode (instance_pos = -1)]
    public void on_colorbutton_clicked(Gtk.Button button) {
        this.colormapper.add_palette(button as PGtk.ColorChooser);
    }

    [CCode (instance_pos = -1)]
    public void on_colorschemes_changed(Gtk.ComboBox widget) {
        if (this.colorschemeignoresignals)
            return;
        var colorscheme = this.colorschemes.get_active_id();
        if (colorscheme == "custom")
            return;
        this.colormapper.color_scheme = colorscheme;
        restore_colorscheme();
    }

    // restore all colors and dropdown to colorscheme from dconf
    // also used by revert from advanced preferences dialog
    public void restore_colorscheme() {
        var colorscheme = this.colormapper.color_scheme;
        this.colorschemeignoresignals = true;
        this.colorgsettings_foreach((settings, key, widget, name) => {
            settings.set_string(key, colorscheme + ":" + name);
        });
        if (this.preferences != null && !this.colorschemes.set_active_id(colorscheme)) {
            this.colorschemes.set_active_id("custom");
        }
        this.colorschemeignoresignals = false;
    }

    // check whether any color was changed from scheme default
    // set dropdown to custom in this case
    private void update_activecolorscheme() {
        if (this.preferences == null || this.colorschemeignoresignals)
            return;

        var colorscheme = this.colormapper.color_scheme;
        var custom = false;
        this.colorgsettings_foreach((settings, key, widget, name) => {
            custom |= settings.get_string(key) != colorscheme + ":" + name;
        });

        this.colorschemeignoresignals = true;
        if (custom || !this.colorschemes.set_active_id(colorscheme)) {
            this.colorschemes.set_active_id("custom");
        }
        this.colorschemeignoresignals = false;
    }

    private void colorgsettings_foreach(ColorForeachFunc callback) {
        foreach (var graphid in this.prefsettings.get_strv("graphs")) {
            if (!(graphid in SettingsCache.presetgraphids))
                continue;

            var graphsettings = this.settingscache.graphsettings(graphid);
            foreach (var traceid in graphsettings.get_strv("traces")) {
                var tracesettings = this.settingscache.tracesettings(graphid, traceid);
                var widget = this.builder == null ?
                    null : this.builder.get_object(@"$(traceid)-color");
                callback(tracesettings, "color", widget, traceid);
            }
        }

        var widget = this.builder == null ?
            null : this.builder.get_object("background-color");
        callback(prefsettings, "background-color", widget, "background");
    }
}

