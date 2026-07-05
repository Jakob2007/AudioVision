
import logging
logging.getLogger("moderngl_window").setLevel(logging.WARNING)
logging.getLogger("moderngl_window.context.base.window").setLevel(logging.WARNING)
logging.getLogger("moderngl_window.context.pyglet").setLevel(logging.WARNING)

from dotenv import load_dotenv
load_dotenv()

import os
import threading
import numpy as np
import platform
import time
import requests
import subprocess

from dataclasses import dataclass, field
from collections import deque

import moderngl
import moderngl_window as mglw
from PIL import Image, ImageDraw, ImageFont

import syncedlyrics as sl
import pylrc

import spotipy
from spotipy.oauth2 import SpotifyOAuth

import qrcode
from qrcode.image.styledpil import StyledPilImage
from qrcode.image.styles.moduledrawers.pil import RoundedModuleDrawer
from qrcode.image.styles.colormasks import SolidFillColorMask

DO_LYRIC_FETCHING = True

# ! Check if queue actually works

"""
TODO:

song cover animation von https://itunes.apple.com/search?term=Radiohead+Creep&entity=song&limit=1 
lyric display
(js texts)
lrclib lyrics integrieren
do sth with spotify beat detection (depricated?)
include jam link (has to be typed in)
"""

class SystemDeviceManager:
    ROUTER = "BlackHole 2ch"
    DEAFULT_GAIN = 1.7

    def __init__(self):
        import sounddevice as sd

        self.active: bool = True
        self.active_lock: bool = False

        self.audio_switch_path: str = os.path.join(os.path.dirname(os.path.realpath(__file__)), "SwitchAudio")
        self.all_devices = sd.query_devices()

        self.output_gain: float = self.DEAFULT_GAIN
        default_output_index = sd.default.device[1]
        if default_output_index is not None:
            self.default_device_name = sd.query_devices(default_output_index)["name"]
        else:
            raise(Exception("No deafult device"))

        self.set_system_output_device(self.ROUTER)

    def set_system_output_device(self, name: str):
        import subprocess
        subprocess.run([self.audio_switch_path, "output", name], check=False)

    def set_active(self, val: bool):
        if not self.active_lock:
            self.active = val

    def toggle_free(self):
        self.active = not self.active
        if self.active:
            self.active_lock = False
            self.set_system_output_device(self.ROUTER)
        else:
            self.active_lock = True
            self.set_system_output_device(self.default_device_name)

    def close(self):
        print("closing to " + self.default_device_name)
        if self.default_device_name:
            self.set_system_output_device(self.default_device_name)

class LrcManager:
    current_lyrics: list = []
    current_id: str = ""
    queued_lyrics: list = []
    queue_id: str = ""

    running: bool = True
    timer_thread: threading.Thread = None
    progress_ms: int = 0
    last_update_time_sec: float = 0
    last_update_ms: int = 0

    def progress_timer_counter(self):
        step_sec = 10 * 0.001
        while self.running:
            now = time.perf_counter()
            delta_progress_ms = (now - self.last_update_time_sec)*1000
            self.progress_ms = round(self.last_update_ms + delta_progress_ms)
            time.sleep(step_sec)

    def __init__(self):
        t = threading.Thread(target=self.progress_timer_counter, daemon=True, name="exact timer")
        t.start()
        self.timer_thread = t

    def set_time_ms(self, progress_ms):
        self.last_update_time_sec = time.perf_counter()
        self.last_update_ms = progress_ms
        self.progress_ms = progress_ms

    def end(self):
        self.running = False
        self.timer_thread.join(timeout=1)
    
    # def get_lyrics_lrclib(track_name, artist, album, duration_sec):
    #     url = "https://lrclib.net/api/get"
    #     "?artist_name=Borislav+Slavov&track_name=I+Want+to+Live&album_name=Baldur%27s+Gate+3+(Original+Game+Soundtrack)&duration=233"
    #     params =  {
    #         "artist_name"   : artist,
    #         "track_name"    : track_name,
    #         "album_name"    : album,
    #         "duration"      : duration_sec
    #     }
    #     result = requests.get(url, params=params)

    #     if result.status_code != 200:
    #         return dict()
        
    #     json = result.json()
    #     json["syncedLyrics"]


    def get_lyrics(self, track_name, artist) -> list:
        # * Handle few cases where there is word timestamps (enhanced=True)
        try:
            result = sl.search(f"{track_name} {artist}", enhanced=False, synced_only=True)
        except:
            return list()
        if not result:
            return list()
        try:
            lyrics = list(pylrc.parse(result))
        except:
            return list()

        return lyrics
    
    def await_lyrics(self, track_name, artist, target):
        if not DO_LYRIC_FETCHING: 
            return
        
        target.clear()
        target.extend(self.get_lyrics(track_name, artist))

    def set_current_song(self, track_name, artist):
        id = track_name + artist
        if id == self.current_id:
            return
        
        if id == self.queue_id:
            self.current_lyrics = self.queued_lyrics
            print("used queue")
            return
        
        threading.Thread(target=self.await_lyrics, daemon=True, name="lyric retrival", args=[track_name, artist, self.current_lyrics]).start()
    
    def queue_song(self, track_name, artist):
        id = track_name + artist
        if id == self.queue_id:
            return
        
        if id == self.current_id:
            return
        
        self.queue_id = id
        threading.Thread(target=self.await_lyrics, daemon=True, name="lyric retrival", args=[track_name, artist, self.queued_lyrics]).start()

    def get_line(self):
        if not self.current_lyrics:
            return ""
        
        progress_sec = self.progress_ms * 0.001
        
        for i,line in enumerate(self.current_lyrics[:-1]):
            nxt = self.current_lyrics[i+1]
            if nxt.time >= progress_sec:
                return line.text.strip()
        
        return ""



# ── Shared State ─────────────────────────────────────────────────────────────

@dataclass
class AppState:
    fft_data:    np.ndarray       = field(default_factory=lambda: np.zeros(512))
    fft_lock:    threading.Lock   = field(default_factory=threading.Lock)

    stop_event:  threading.Event  = field(default_factory=threading.Event)
    spotify_api: spotipy.Spotify  = None
    devices: SystemDeviceManager  = None
    lyrics: LrcManager            = None

    is_new_song: bool = True

    track_name:  str = ""
    artist:      str = ""
    album:       str = ""
    track_id:    str = ""
    bpm:         float = 0
    spotify_volume: int = 50
    duration_ms: int = 0
    progress_ms: int = 0

    request_upcoming_data: bool = False
    next_track_name:  str = ""
    next_artist:      str = ""
    next_album:       str = ""

    do_quick_info: bool = True
    request_info: bool = False

    jam_url: str = "https://pbs.twimg.com/media/G3pBT_PXkAAyVDC.jpg"


    def __str__(self):
        return f"Title: {self.track_name} by {self.artist}"


# ── Audio Thread ──────────────────────────────────────────────────────────────

def start_audio_thread(state: AppState) -> threading.Thread:
    from scipy.signal import windows
    import sounddevice as sd

    def get_device_index(name):
        devices = sd.query_devices()
        return next(i for i, d in enumerate(devices) if name in d["name"] and d["max_output_channels"] == 2)

    # Find BlackHole input and a valid output device for instant replay
    black_hole_index = get_device_index(SystemDeviceManager.ROUTER)
    out_index = get_device_index(state.devices.default_device_name)
    print("Playing on: ", state.devices.default_device_name, out_index)

    CHUNK = 2048
    SR = 44100
    hann = windows.hann(CHUNK)
    raw_buffer = deque(maxlen=CHUNK)

    def audio_callback(indata, outdata, frames, time, status):
        raw_buffer.extend(indata[:, 0])
        if len(raw_buffer) >= CHUNK:
            chunk = np.array(raw_buffer)
            spectrum = np.abs(np.fft.rfft(chunk * hann))[:512]
            log_spec = np.log1p(spectrum)
            normalized = log_spec / (log_spec.max() + 1e-8)
            with state.fft_lock:
                state.fft_data[:] = state.fft_data * 0.7 + normalized * 0.3
        out = indata * state.devices.output_gain
        out = np.clip(out, -1.0, 1.0)
        outdata[:] = out

    def run():
        with sd.Stream(
            device=(black_hole_index, out_index),
            samplerate=SR,
            blocksize=1024,
            channels=2,
            callback=audio_callback,
        ):
            state.stop_event.wait()

    t = threading.Thread(target=run, daemon=True, name="audio")
    t.start()
    return t


# ── Spotify Thread ────────────────────────────────────────────────────────────

def start_spotify_thread(state: AppState) -> threading.Thread:
    sp = None
    try:
        sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
            scope="user-read-playback-state user-modify-playback-state",
            cache_path=".spotify_cache",
        ))
    except:
        print("Spotify failed")

    state.spotify_api = sp

    def run():
        while not state.stop_event.is_set() and sp:
            pb = None
            pb = sp.current_playback()
            # get if playing
            state.devices.set_active(pb is not None and pb.get("is_playing"))
            try:
                if pb and pb["is_playing"]:
                    # get current track
                    track = pb["item"]
                    new_track_id        = track["id"]
                    state.is_new_song   = new_track_id != state.track_id
                    state.track_id      = new_track_id
                    state.track_name    = track["name"]
                    state.artist        = track["artists"][0]["name"]
                    state.progress_ms   = pb["progress_ms"]
                    state.album         = track["album"]["name"]
                    state.duration_ms   = track["duration_ms"]
                    state.lyrics.set_time_ms(state.progress_ms)
            except Exception:
                pass

            if state.is_new_song:
                state.request_upcoming_data = False
                state.next_track_name = None

            # get upcoming track data
            if not state.next_track_name or state.next_track_name == state.track_name or state.request_upcoming_data:
                try:
                    queue = sp.queue()
                    if queue and queue["queue"]:
                        nxt = queue["queue"][0]
                        state.next_track_name = nxt["name"]
                        state.next_artist     = nxt["artists"][0]["name"]
                        state.next_album      = nxt["album"]["name"]
                except Exception:
                    pass
                if state.next_track_name:
                    state.lyrics.queue_song(state.next_track_name, state.next_artist)

            # get lyrics
            if state.is_new_song:
                try:
                    state.lyrics.set_current_song(state.track_name, state.artist)
                except Exception:
                    pass

            # * depricated
            # # get audio analysis 
            # if state.is_new_song:
            #     try:
            #         analysis = sp.audio_analysis(state.track_id)
            #         state.beats = analysis["beats"]
            #         pass
            #     except Exception:
            #         pass

            state.stop_event.wait(timeout=1.0)

    t = threading.Thread(target=run, daemon=True, name="spotify")
    t.start()
    return t


# ── Renderer ──────────────────────────────────────────────────────────────────

class Visualizer(mglw.WindowConfig):
    title = "Visualizer"
    gl_version = (4, 1)
    window_size = (1920, 1080)
    state: AppState = None
    song_transition_time_ms: int = 2000

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        def get_glsl_version():
            return "410 core" if platform.system() == "Darwin" else "300 es"
        self.get_glsl_version = get_glsl_version

        base_dir = os.path.dirname(os.path.realpath(__file__))
        self.shader_dir = os.path.join(base_dir, "shaders")
        self.vert_path = os.path.join(base_dir, "vert.glsl")
        self.vert_src = self.load_file(self.vert_path)

        self.shaders = []
        self.shader_index = 0
        self.reload_shaders()

        self.time = 0.0

        # info shader
        self.info_prog = self.ctx.program(
            vertex_shader=self.vert_src,
            fragment_shader=self.load_file(os.path.join(base_dir, "info.glsl"))
        )

        # idle shader
        self.idle_prog = self.ctx.program(
            vertex_shader=self.vert_src,
            fragment_shader=self.load_file(os.path.join(base_dir, "idle.glsl"))
        )

        # textures
        self.fft_tex = self.ctx.texture((512, 1), components=1, dtype="f4")
        self.info_tex = self.ctx.texture((1920, 1080), components=4, dtype="f1")
        self.info_tex.filter = (moderngl.LINEAR, moderngl.LINEAR)
        self.overlay_tex = self.ctx.texture((1920, 1080), components=4, dtype="f1")
        self.overlay_tex.filter = (moderngl.LINEAR, moderngl.LINEAR)
        self.quad = mglw.geometry.quad_fs()

        # lyric state
        self.last_lyric = ""

        # info state
        self.info_active   = False
        self.info_start    = 0.0
        self.info_duration = 4.0
        self.fade_duration    = 1.0

        # idle state
        self.idle_main_alpha = 1.0   # 1.0 = main fully visible, 0.0 = faded out
        self.idle_fade_alpha = 0.0   # 0.0 = idle hidden, 1.0 = idle fully visible
        self.idle_fade_in    = 5.0   # seconds for idle to fade in after main fades out
        self.idle_fade_out   = 1.5   # seconds for main to fade out before idle starts
    
    # ─── file loading ────────────────────────────────────────────────

    def load_file(self, path):
        with open(path, "r") as f:
            content = f.read()
        content = content.replace("${GLSL_VERSION}", self.get_glsl_version())
        content = content.replace("${PRECISION}", ("" if platform.system() == "Darwin" else "precision highp float;"))
        return content

    # ─── shader management ───────────────────────────────────────────

    def reload_shaders(self):
        self.shaders = sorted([
            f for f in os.listdir(self.shader_dir)
            if f.endswith(".glsl") and not f.startswith(("vert", "info", "idle"))
        ])
        self.shader_index = max(0, min(self.shader_index, len(self.shaders) - 1))
        self.build_program()

    def build_program(self):
        if not self.shaders:
            return
        frag_path = os.path.join(self.shader_dir, self.shaders[self.shader_index])
        self.prog = self.ctx.program(
            vertex_shader=self.vert_src,
            fragment_shader=self.load_file(frag_path)
        )

    def next_shader(self):
        self.shader_index = (self.shader_index + 1) % len(self.shaders)
        self.build_program()

    def prev_shader(self):
        self.shader_index = (self.shader_index - 1) % len(self.shaders)
        self.build_program()

    # ─── idle alpha ──────────────────────────────────────────────────

    def update_idle_alpha(self, frame_time: float):
        active = self.state.devices.active

        if not active:
            if self.idle_main_alpha > 0.0:
                # phase 1: fade out main shader first
                step = frame_time / self.idle_fade_out
                self.idle_main_alpha = max(0.0, self.idle_main_alpha - step)
            else:
                # phase 2: only start fading in idle once main is fully gone
                step = frame_time / self.idle_fade_in
                self.idle_fade_alpha = min(1.0, self.idle_fade_alpha + step)
        else:
            # instant snap back — idle off, main fully on
            self.idle_main_alpha = 1.0
            self.idle_fade_alpha = 0.0

    # ─── info texture ────────────────────────────────────────────────

    def render_info_texture(self, track_name: str, artist: str, album: str):
        img = Image.new("RGBA", (1920, 1080), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)

        try:
            font_large  = ImageFont.truetype("/System/Library/Fonts/Zapfino.ttf", 96)
            font_medium = ImageFont.truetype("/System/Library/Fonts/Zapfino.ttf", 52)
            font_small  = ImageFont.truetype("/System/Library/Fonts/Zapfino.ttf", 38)
        except Exception:
            font_large = font_medium = font_small = ImageFont.load_default()

        # QR-Code erzeugen und gestalterisch aufbereiten
        qr = qrcode.QRCode(
            version=None,
            error_correction=qrcode.constants.ERROR_CORRECT_H,
            box_size=10,
            border=2,
        )

        try:
            qr.add_data(self.state.jam_url)
            qr.make(fit=True)
        except:
            qr.add_data("https://pbs.twimg.com/media/G3pBT_PXkAAyVDC.jpg")
            qr.make(fit=True)

        qr_img = qr.make_image(
            image_factory=StyledPilImage,
            module_drawer=RoundedModuleDrawer(),
            color_mask=SolidFillColorMask(
                front_color=(200, 200, 220),
                back_color=(20, 20, 30),
            ),
        ).convert("RGBA")
        

        # Größe auf der rechten Seite bestimmen
        qr_size = 260
        qr_img = qr_img.resize((qr_size, qr_size), Image.LANCZOS)

        # Dezente Transparenz, damit sich der Code einfügt
        alpha = qr_img.split()[3].point(lambda a: int(a * 0.85))
        qr_img.putalpha(alpha)

        margin = 100
        qr_x = 1920 - qr_size - margin
        qr_y = int((1080 - qr_size) * .9)
        img.alpha_composite(qr_img, (qr_x, qr_y))

        # Next song in bottom right
        next_name, next_artist, next_album = self.get_next_track_info()
        if next_name != track_name:
            font_next = ImageFont.truetype("/System/Library/Fonts/Avenir Next.ttc", 24)
            next_text = f"Next: {next_name[:30]} by {next_artist[:20]}"
            draw.text((1920 - margin + 20, 1080 - 40), next_text, font=font_next,
                      fill=(140, 140, 160, 120), anchor="rm")

        cx = 960
        draw.text((cx, 420), track_name, font=font_large,
                  fill=(255, 255, 255, 255), anchor="mm")
        draw.text((cx, 540), artist, font=font_medium,
                  fill=(200, 200, 220, 200), anchor="mm")
        draw.text((cx, 620), album, font=font_small,
                  fill=(140, 140, 160, 160), anchor="mm")

        img = img.transpose(Image.FLIP_TOP_BOTTOM)
        self.info_tex.write(img.tobytes())

    # ─── overlay texture ────────────────────────────────────────────────

    def render_overlay_texture(self, line):
        img = Image.new("RGBA", (1920, 1080), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)

        font  = ImageFont.truetype("/System/Library/Fonts/Avenir Next.ttc", 52)

        cx = 960
        draw.text((cx, 750), line, font=font, fill=(255, 255, 255, 255), anchor="mm")

        img = img.transpose(Image.FLIP_TOP_BOTTOM)
        self.overlay_tex.write(img.tobytes())

    # ─── jam ────────────────────────────────────────────────────────────

    def set_new_jam_key(self):
        def set_j(self):
            prompt = "Please enter jam url:"
            skript = (
                f'display dialog "{prompt}" default answer "{self.state.jam_url}" '
                f'buttons {{"Cancel", "OK"}} default button "OK"\n'
                f'return text returned of result'
            )

            result = subprocess.run(
                ["osascript", "-e", skript],
                capture_output=True,
                text=True
            )

            if result.returncode != 0:
                return

            link = result.stdout.strip()

            if not link:
                return

            self.state.jam_url = link

            self.state.request_info = True

        threading.Thread(target=set_j, daemon=True, name="jam key popup", args=[self]).start()

    # ─── info trigger ─────────────────────────────────────────────

    def should_get_next_song_data(self) -> bool:
        progress = self.state.progress_ms
        duration = self.state.duration_ms
        if duration <= 0 or progress <= 0:
            return False
        leftover_time = duration - progress
        return leftover_time <= self.song_transition_time_ms + 2000 and leftover_time >= self.song_transition_time_ms + 1000

    def should_trigger_info(self) -> bool:
        progress = self.state.progress_ms
        duration = self.state.duration_ms
        if duration <= 0 or progress <= 0:
            return False
        return (duration - progress) <= self.song_transition_time_ms

    def trigger_info(self):
        if self.state.devices.active_lock:
            return False
        self.info_active = True
        self.info_start  = self.time

    def interrupt_info(self):
        self.info_active = False

    def info_alpha(self, time: float) -> float:
        if not self.info_active:
            return 0.0
        elapsed = time - self.info_start
        total   = self.info_duration + self.fade_duration * 2
        if elapsed > total:
            self.info_active = False
            self.state.do_quick_info = False
            return 0.0
        if elapsed < self.fade_duration:
            return 1.0 if self.state.do_quick_info else elapsed / self.fade_duration
        if elapsed < self.fade_duration + self.info_duration:
            return 1.0
        return 1.0 - (elapsed - self.fade_duration - self.info_duration) / self.fade_duration

    def get_next_track_info(self):
        name   = self.state.next_track_name or self.state.track_name
        artist = self.state.next_artist     or self.state.artist
        album  = self.state.next_album      or self.state.album
        return name, artist, album

    # ─── uniforms ────────────────────────────────────────────────────

    def set_uniform(self, prog, name, value):
        if name in prog:
            prog[name] = value

    def upload_main_uniforms(self):
        self.fft_tex.use(location=0)
        self.overlay_tex.use(location=1)
        self.set_uniform(self.prog, "iFFT",  0)
        self.set_uniform(self.prog, "iText",  1)
        self.set_uniform(self.prog, "iTime", self.time)
        self.set_uniform(self.prog, "iBPM",  self.state.bpm)
        self.set_uniform(self.prog, "iRes",  tuple(self.wnd.size))
        self.set_uniform(self.prog, "iAlpha", self.idle_main_alpha)

    def upload_info_uniforms(self, alpha: float):
        self.fft_tex.use(location=0)
        self.info_tex.use(location=1)
        self.set_uniform(self.info_prog, "iFFT",   0)
        self.set_uniform(self.info_prog, "iText",  1)
        self.set_uniform(self.info_prog, "iTime",  self.time)
        self.set_uniform(self.info_prog, "iAlpha", alpha)
        self.set_uniform(self.info_prog, "iRes",   tuple(self.wnd.size))

    def upload_idle_uniforms(self, alpha: float):
        self.fft_tex.use(location=0)
        self.set_uniform(self.idle_prog, "iFFT",   0)
        self.set_uniform(self.idle_prog, "iTime",  self.time)
        self.set_uniform(self.idle_prog, "iAlpha", alpha)
        self.set_uniform(self.idle_prog, "iRes",   tuple(self.wnd.size))

    # ─── render loop ─────────────────────────────────────────────────

    def render(self, time: float, frame_time: float):
        self.time = time
        self.ctx.clear()

        # ── update idle state ─────────────────────────────────────────
        self.update_idle_alpha(frame_time)

        # ── track change detection ────────────────────────────────────
        track_id = getattr(self.state, "track_id", None)

        if self.should_get_next_song_data() and not self.state.request_upcoming_data:
            self.state.request_upcoming_data = True

        if not self.info_active and self.should_trigger_info():
            next_name, next_artist, next_album = self.get_next_track_info()
            self.render_info_texture(next_name, next_artist, next_album)
            self.trigger_info()

        elif self.state.is_new_song:
            self.state.request_info = True
        
        if self.state.request_info:
            self.state.request_info = False
            self.state.do_quick_info = True
            self.render_info_texture(
                self.state.track_name,
                self.state.artist,
                self.state.album,
            )
            self.trigger_info()

        # ── render overlay ────────────────────────────────────────────
        line = self.state.lyrics.get_line()
        if self.last_lyric != line:
            self.render_overlay_texture(line)
            self.last_lyric = line

        # ── upload FFT ────────────────────────────────────────────────
        with self.state.fft_lock:
            fft_copy = self.state.fft_data.astype("f4")
        self.fft_tex.write(fft_copy.tobytes())

        o_alpha = self.info_alpha(time)

        # ── draw layers ───────────────────────────────────────────────
        #
        #  Layer order (back to front):
        #    1. main shader      (always rendered as base)
        #    2. idle shader      (blended on top, slow fade in/instant off)
        #    3. info shader   (blended on top of everything)
        #
        # Idle and info can coexist: e.g. song ends → idle fades in,
        # next song detected → info fires on top, then idle snaps off
        # when playback resumes.

        # layer 1 — main (fades out when idle kicks in)
        if self.idle_main_alpha > 0.001:
            if self.idle_main_alpha < 0.999:
                self.ctx.enable(moderngl.BLEND)
                self.ctx.blend_func = moderngl.SRC_ALPHA, moderngl.ONE_MINUS_SRC_ALPHA
                self.set_uniform(self.prog, "iAlpha", self.idle_main_alpha)
            self.upload_main_uniforms()
            self.quad.render(self.prog)
            if self.idle_main_alpha < 0.999:
                self.ctx.disable(moderngl.BLEND)

        # layer 2 — idle (only begins after main is fully faded)
        if self.idle_fade_alpha > 0.001:
            self.ctx.enable(moderngl.BLEND)
            self.ctx.blend_func = moderngl.SRC_ALPHA, moderngl.ONE_MINUS_SRC_ALPHA
            self.upload_idle_uniforms(self.idle_fade_alpha)
            self.quad.render(self.idle_prog)
            self.ctx.disable(moderngl.BLEND)

        # layer 3 — info (song info card)
        if o_alpha > 0.001:
            self.ctx.enable(moderngl.BLEND)
            self.ctx.blend_func = moderngl.SRC_ALPHA, moderngl.ONE_MINUS_SRC_ALPHA
            self.upload_info_uniforms(o_alpha)
            self.quad.render(self.info_prog)
            self.ctx.disable(moderngl.BLEND)

    # ─── input ───────────────────────────────────────────────────────

    def key_event(self, key, action, modifiers):
        if action != self.wnd.keys.ACTION_PRESS:
            return

        #close
        if key == self.wnd.keys.ESCAPE:
            self.state.stop_event.set()
            self.wnd.close()

        # shader control
        elif key == self.wnd.keys.Q:
            self.interrupt_info()
            self.prev_shader()
        elif key == self.wnd.keys.E:
            self.interrupt_info()
            self.next_shader()
        elif key == self.wnd.keys.R:
            self.interrupt_info()
            self.reload_shaders()

        # info
        elif key == self.wnd.keys.I:
            if self.info_active:
                self.interrupt_info()
            else:
                print(self.state)
                self.state.request_info = True

        # gain control
        elif key == self.wnd.keys.A:
            self.state.devices.output_gain -= 0.7
        elif key == self.wnd.keys.S:
            self.state.devices.output_gain = SystemDeviceManager.DEAFULT_GAIN
        elif key == self.wnd.keys.D:
            self.state.devices.output_gain += 0.7

        # toggle free
        elif key == self.wnd.keys.F:
            self.state.devices.toggle_free()
            if self.state.devices.active:
                self.trigger_info()
            else:
                self.interrupt_info()

        # spotify control
        elif key == self.wnd.keys.SPACE:
            try:
                sp = self.state.spotify_api
                is_playing = sp.current_playback()["is_playing"]
                if is_playing:
                    sp.pause_playback()
                else:
                    sp.start_playback()
            except Exception:
                pass
        elif key == self.wnd.keys.N:
            try:
                sp = self.state.spotify_api
                sp.next_track()
                self.trigger_info()
            except Exception:
                pass
        
        # jam control
        elif key == self.wnd.keys.J:
            self.set_new_jam_key()

# ── Einstiegspunkt ────────────────────────────────────────────────────────────

def main():
    state = AppState()

    state.devices = SystemDeviceManager()
    state.lyrics = LrcManager()

    # Threads starten
    audio_thread = start_audio_thread(state)
    spotify_thread = start_spotify_thread(state)

    # Renderer bekommt Zugriff auf State (Klassenattribut als DI)
    Visualizer.state = state

    try:
        mglw.run_window_config(Visualizer)
    except KeyboardInterrupt:
        pass
    finally:
        state.devices.close()
        state.lyrics.end()
        state.stop_event.set()
        audio_thread.join(timeout=2)
        spotify_thread.join(timeout=2)


if __name__ == "__main__":
    main()