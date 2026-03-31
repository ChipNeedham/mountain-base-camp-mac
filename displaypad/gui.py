"""Simple tkinter GUI for DisplayPad macOS configuration.

Shows a visual representation of the 12-key grid and allows
configuring macros for each key.
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog, simpledialog
import threading
from PIL import Image, ImageTk

from .config import load_config, save_config, DEFAULT_CONFIG
from .device import DisplayPad, NUM_KEYS, NUM_KEYS_PER_ROW, ICON_SIZE
from .icons import (
    create_text_icon, create_spotify_icon, create_api_icon, load_icon
)
from .macros import (
    MacroEngine, Macro,
    spotify_play_pause, spotify_next, spotify_previous,
    spotify_volume_up, spotify_volume_down, spotify_get_current_track,
    make_api_call, run_shell_command, open_app, send_keystrokes,
)

MACRO_TYPES = ["none", "spotify", "api", "shell", "app", "keystroke"]

SPOTIFY_ACTIONS = {
    "play_pause": ("Play/Pause", spotify_play_pause),
    "next": ("Next Track", spotify_next),
    "previous": ("Previous Track", spotify_previous),
    "vol_up": ("Volume Up", spotify_volume_up),
    "vol_down": ("Volume Down", spotify_volume_down),
    "now_playing": ("Now Playing", lambda: print(spotify_get_current_track())),
}


class DisplayPadApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("DisplayPad Controller")
        self.root.geometry("800x600")
        self.root.configure(bg="#1a1a2e")

        self.device = None
        self.engine = MacroEngine()
        self.config = load_config()
        self.key_buttons = []
        self.key_images = {}  # keep references to prevent GC

        self._build_ui()

    def _build_ui(self):
        # ── Status bar ──
        status_frame = tk.Frame(self.root, bg="#16213e", height=40)
        status_frame.pack(fill=tk.X, padx=0, pady=0)

        self.status_label = tk.Label(
            status_frame, text="Disconnected", fg="#e94560",
            bg="#16213e", font=("Helvetica", 12)
        )
        self.status_label.pack(side=tk.LEFT, padx=10, pady=8)

        self.connect_btn = tk.Button(
            status_frame, text="Connect", command=self._connect_device,
            bg="#0f3460", fg="white", font=("Helvetica", 11),
            relief=tk.FLAT, padx=15
        )
        self.connect_btn.pack(side=tk.RIGHT, padx=10, pady=5)

        self.push_btn = tk.Button(
            status_frame, text="Push to Device", command=self._push_all,
            bg="#533483", fg="white", font=("Helvetica", 11),
            relief=tk.FLAT, padx=15, state=tk.DISABLED
        )
        self.push_btn.pack(side=tk.RIGHT, padx=5, pady=5)

        # ── Key grid (6x2) ──
        grid_frame = tk.Frame(self.root, bg="#1a1a2e")
        grid_frame.pack(expand=True, pady=20)

        for row in range(2):
            for col in range(NUM_KEYS_PER_ROW):
                key_idx = row * NUM_KEYS_PER_ROW + col
                btn = tk.Button(
                    grid_frame, text=f"Key {key_idx + 1}",
                    width=10, height=5,
                    bg="#2d2d44", fg="white",
                    activebackground="#3d3d55",
                    font=("Helvetica", 10),
                    relief=tk.RAISED, bd=2,
                    command=lambda idx=key_idx: self._configure_key(idx)
                )
                btn.grid(row=row, column=col, padx=6, pady=6, sticky="nsew")
                self.key_buttons.append(btn)

        # Make grid cells equal size
        for col in range(NUM_KEYS_PER_ROW):
            grid_frame.columnconfigure(col, weight=1, minsize=110)
        for row in range(2):
            grid_frame.rowconfigure(row, weight=1, minsize=110)

        # ── Info panel ──
        info_frame = tk.Frame(self.root, bg="#1a1a2e")
        info_frame.pack(fill=tk.X, padx=20, pady=10)

        tk.Label(
            info_frame,
            text="Click a key to configure its macro. Connect device to push icons and enable buttons.",
            fg="#888", bg="#1a1a2e", font=("Helvetica", 11)
        ).pack()

        # ── Bottom buttons ──
        bottom_frame = tk.Frame(self.root, bg="#1a1a2e")
        bottom_frame.pack(fill=tk.X, padx=20, pady=10)

        tk.Button(
            bottom_frame, text="Save Config", command=self._save,
            bg="#0f3460", fg="white", font=("Helvetica", 11),
            relief=tk.FLAT, padx=15
        ).pack(side=tk.LEFT, padx=5)

        tk.Button(
            bottom_frame, text="Reset Defaults", command=self._reset_defaults,
            bg="#5c3d2e", fg="white", font=("Helvetica", 11),
            relief=tk.FLAT, padx=15
        ).pack(side=tk.LEFT, padx=5)

        # Load existing config into UI
        self._refresh_key_display()

    def _refresh_key_display(self):
        """Update button labels/colors from config."""
        keys = self.config.get("keys", {})
        for i in range(NUM_KEYS):
            key_cfg = keys.get(str(i), {"type": "none", "label": ""})
            label = key_cfg.get("label", f"Key {i+1}")
            macro_type = key_cfg.get("type", "none")

            btn = self.key_buttons[i]

            if macro_type == "spotify":
                btn.configure(bg="#1DB954", fg="black", text=label or "Spotify")
            elif macro_type == "api":
                btn.configure(bg="#4285F4", fg="white", text=label or "API")
            elif macro_type == "shell":
                btn.configure(bg="#FF6B35", fg="white", text=label or "Shell")
            elif macro_type == "app":
                btn.configure(bg="#9B59B6", fg="white", text=label or "App")
            elif macro_type == "keystroke":
                btn.configure(bg="#E67E22", fg="white", text=label or "Keys")
            else:
                btn.configure(bg="#2d2d44", fg="#666", text=label or f"Key {i+1}")

    def _configure_key(self, key_idx):
        """Open configuration dialog for a key."""
        dialog = KeyConfigDialog(self.root, key_idx, self.config)
        self.root.wait_window(dialog.top)

        if dialog.result:
            self.config.setdefault("keys", {})[str(key_idx)] = dialog.result
            self._refresh_key_display()
            self._rebuild_macros()

    def _rebuild_macros(self):
        """Rebuild macro registrations from config."""
        self.engine = MacroEngine()
        keys = self.config.get("keys", {})

        for key_str, key_cfg in keys.items():
            key_idx = int(key_str)
            macro_type = key_cfg.get("type", "none")

            if macro_type == "none":
                continue

            action = None
            icon = create_text_icon(key_cfg.get("label", "?"))

            if macro_type == "spotify":
                spotify_action = key_cfg.get("action", "play_pause")
                if spotify_action in SPOTIFY_ACTIONS:
                    _, action = SPOTIFY_ACTIONS[spotify_action]
                    icon = create_spotify_icon(
                        key_cfg.get("label", spotify_action), action=spotify_action
                    )

            elif macro_type == "api":
                url = key_cfg.get("url", "https://httpbin.org/get")
                method = key_cfg.get("method", "GET")
                headers = key_cfg.get("headers", {})
                body = key_cfg.get("body", None)
                action = make_api_call(url, method, headers, body)
                icon = create_api_icon(key_cfg.get("label", "API"))

            elif macro_type == "shell":
                cmd = key_cfg.get("command", "echo hello")
                action = run_shell_command(cmd)

            elif macro_type == "app":
                app = key_cfg.get("app_name", "Finder")
                action = open_app(app)

            elif macro_type == "keystroke":
                keys_str = key_cfg.get("keys", 'keystroke "v" using command down')
                action = send_keystrokes(keys_str)

            if action:
                macro = Macro(
                    name=key_cfg.get("label", f"Key {key_idx}"),
                    key_index=key_idx,
                    icon=icon,
                    on_press=action,
                )
                self.engine.register(macro)

    def _connect_device(self):
        """Try to connect to the DisplayPad (runs in background thread)."""
        self.status_label.configure(text="Connecting...", fg="#FFA500")
        self.connect_btn.configure(state=tk.DISABLED)

        def do_connect():
            try:
                dev = DisplayPad()
                dev.open()
                self.root.after(0, lambda: self._on_connected(dev))
            except Exception as e:
                msg = str(e)
                self.root.after(0, lambda: self._on_connect_failed(msg))

        threading.Thread(target=do_connect, daemon=True).start()

    def _on_connected(self, dev):
        """Called on main thread after successful connection."""
        self.device = dev
        self.device.on_key_down(self.engine.handle_key_down)
        self.device.on_key_up(self.engine.handle_key_up)

        self.status_label.configure(text="Connected", fg="#1DB954")
        self.connect_btn.configure(
            text="Disconnect", command=self._disconnect_device, state=tk.NORMAL
        )
        self.push_btn.configure(state=tk.NORMAL)

        self._rebuild_macros()
        self._push_all()

    def _on_connect_failed(self, error_msg):
        """Called on main thread after failed connection."""
        self.status_label.configure(text="Disconnected", fg="#e94560")
        self.connect_btn.configure(state=tk.NORMAL)
        messagebox.showerror("Connection Failed", error_msg)

    def _disconnect_device(self):
        """Disconnect from the DisplayPad."""
        if self.device:
            self.device.close()
            self.device = None

        self.status_label.configure(text="Disconnected", fg="#e94560")
        self.connect_btn.configure(text="Connect", command=self._connect_device)
        self.push_btn.configure(state=tk.DISABLED)

    def _push_all(self):
        """Queue all configured icons — worker loop (on USB thread) will send them."""
        if not self.device or not self.device.initialized:
            return

        self._rebuild_macros()

        for key_idx in range(NUM_KEYS):
            macro = self.engine.macros.get(key_idx)
            if macro:
                self.device.set_key_image(key_idx, macro.icon)
            else:
                self.device.clear_key(key_idx)

    def _save(self):
        save_config(self.config)
        messagebox.showinfo("Saved", "Configuration saved.")

    def _reset_defaults(self):
        if messagebox.askyesno("Reset", "Reset all keys to defaults?"):
            self.config = DEFAULT_CONFIG.copy()
            self._refresh_key_display()
            self._rebuild_macros()

    def run(self):
        self._rebuild_macros()
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        self.root.mainloop()

    def _on_close(self):
        if self.device:
            self.device.close()
        self.root.destroy()


class KeyConfigDialog:
    """Dialog for configuring a single key's macro."""

    def __init__(self, parent, key_idx, config):
        self.result = None
        self.key_idx = key_idx

        existing = config.get("keys", {}).get(str(key_idx), {"type": "none", "label": ""})

        self.top = tk.Toplevel(parent)
        self.top.title(f"Configure Key {key_idx + 1}")
        self.top.geometry("450x400")
        self.top.configure(bg="#1a1a2e")
        self.top.transient(parent)
        self.top.grab_set()

        # ── Macro type ──
        tk.Label(self.top, text="Macro Type:", fg="white", bg="#1a1a2e",
                 font=("Helvetica", 12)).pack(pady=(15, 5))

        self.type_var = tk.StringVar(value=existing.get("type", "none"))
        type_frame = tk.Frame(self.top, bg="#1a1a2e")
        type_frame.pack()

        for t in MACRO_TYPES:
            tk.Radiobutton(
                type_frame, text=t.capitalize(), variable=self.type_var, value=t,
                fg="white", bg="#1a1a2e", selectcolor="#333",
                activebackground="#1a1a2e", activeforeground="white",
                command=self._on_type_change
            ).pack(side=tk.LEFT, padx=8)

        # ── Label ──
        tk.Label(self.top, text="Label:", fg="white", bg="#1a1a2e",
                 font=("Helvetica", 12)).pack(pady=(15, 5))
        self.label_var = tk.StringVar(value=existing.get("label", ""))
        tk.Entry(self.top, textvariable=self.label_var, width=30,
                 font=("Helvetica", 12)).pack()

        # ── Dynamic options frame ──
        self.options_frame = tk.Frame(self.top, bg="#1a1a2e")
        self.options_frame.pack(fill=tk.X, padx=20, pady=10)

        self.option_vars = {}
        self._on_type_change()

        # Pre-fill options from existing config
        for key, val in existing.items():
            if key in self.option_vars:
                self.option_vars[key].set(val)

        # ── Buttons ──
        btn_frame = tk.Frame(self.top, bg="#1a1a2e")
        btn_frame.pack(pady=15)

        tk.Button(btn_frame, text="Save", command=self._save,
                  bg="#0f3460", fg="white", font=("Helvetica", 11),
                  relief=tk.FLAT, padx=20).pack(side=tk.LEFT, padx=10)
        tk.Button(btn_frame, text="Cancel", command=self.top.destroy,
                  bg="#5c3d2e", fg="white", font=("Helvetica", 11),
                  relief=tk.FLAT, padx=20).pack(side=tk.LEFT, padx=10)

    def _on_type_change(self):
        """Update options based on selected macro type."""
        for widget in self.options_frame.winfo_children():
            widget.destroy()
        self.option_vars = {}

        macro_type = self.type_var.get()

        if macro_type == "spotify":
            tk.Label(self.options_frame, text="Action:", fg="white", bg="#1a1a2e").pack(anchor=tk.W)
            self.option_vars["action"] = tk.StringVar(value="play_pause")
            combo = ttk.Combobox(
                self.options_frame, textvariable=self.option_vars["action"],
                values=list(SPOTIFY_ACTIONS.keys()), state="readonly", width=25
            )
            combo.pack(pady=5)

        elif macro_type == "api":
            for field, default in [("url", "https://httpbin.org/get"), ("method", "GET")]:
                tk.Label(self.options_frame, text=f"{field.upper()}:", fg="white", bg="#1a1a2e").pack(anchor=tk.W)
                self.option_vars[field] = tk.StringVar(value=default)
                tk.Entry(self.options_frame, textvariable=self.option_vars[field], width=40).pack(pady=2)

        elif macro_type == "shell":
            tk.Label(self.options_frame, text="Command:", fg="white", bg="#1a1a2e").pack(anchor=tk.W)
            self.option_vars["command"] = tk.StringVar(value="echo hello")
            tk.Entry(self.options_frame, textvariable=self.option_vars["command"], width=40).pack(pady=2)

        elif macro_type == "app":
            tk.Label(self.options_frame, text="App Name:", fg="white", bg="#1a1a2e").pack(anchor=tk.W)
            self.option_vars["app_name"] = tk.StringVar(value="Finder")
            tk.Entry(self.options_frame, textvariable=self.option_vars["app_name"], width=40).pack(pady=2)

        elif macro_type == "keystroke":
            tk.Label(self.options_frame, text="AppleScript keys:", fg="white", bg="#1a1a2e").pack(anchor=tk.W)
            self.option_vars["keys"] = tk.StringVar(value='keystroke "v" using command down')
            tk.Entry(self.options_frame, textvariable=self.option_vars["keys"], width=40).pack(pady=2)

    def _save(self):
        self.result = {
            "type": self.type_var.get(),
            "label": self.label_var.get(),
        }
        for key, var in self.option_vars.items():
            self.result[key] = var.get()

        self.top.destroy()
