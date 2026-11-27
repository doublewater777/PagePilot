#!/usr/bin/env python3
"""
PagePilot 2.0 App Store Screenshot Studio Generator
Renders cohesive 5-slide marketing screenshot sets for:
  - APP_IPHONE_65 (1284x2778)
  - APP_IPHONE_67 (1290x2796, also valid for APP_IPHONE_69)
  - APP_IPAD_PRO_3GEN_129 (2048x2732)
  - APP_DESKTOP (2880x1800)
across all 5 locales: zh-Hans, en-US, es-ES, fr-FR, de-DE.

Uses AI-generated studio backdrops, AI-generated literary book covers,
real localized Apple Watch screenshots, and exact PagePilot 2.0 UI tokens.
Outputs alpha-free sRGB PNGs validated by `asc screenshots validate`.
"""

import argparse
import base64
import concurrent.futures
import html
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from PIL import Image

REPO_ROOT = Path("/Users/water/Desktop/dev/PagePilot")
ART_DIR = REPO_ROOT / "screenshots" / "art"
WATCH_DIR = REPO_ROOT / "screenshots" / "watch"
OUT_ROOT = REPO_ROOT / "screenshots" / "export" / "store-v2"
CHROME_BIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRGB_ICC = Path("/System/Library/ColorSync/Profiles/sRGB IEC61966-2.1.icc")

SAMPLE_COVER = (
    REPO_ROOT
    / "Sources"
    / "Resources"
    / "Assets.xcassets"
    / "SampleBookCover.imageset"
    / "sample_book_cover.jpg"
)
APP_ICON = (
    REPO_ROOT
    / "Sources"
    / "Resources"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "Icon-1024.png"
)

DEVICES = {
    "APP_IPHONE_65": {"w": 1284, "h": 2778, "family": "iphone"},
    "APP_IPHONE_67": {"w": 1290, "h": 2796, "family": "iphone"},
    "APP_IPAD_PRO_3GEN_129": {"w": 2048, "h": 2732, "family": "ipad"},
    "APP_DESKTOP": {"w": 2880, "h": 1800, "family": "mac"},
}

SLIDES = [
    "01_handsfree_watch",
    "02_desk_micro_reading",
    "03_paper_presets",
    "04_journal_postcard",
    "05_ecosystem_sync",
]

LOCALES = ["zh-Hans", "en-US", "es-ES", "fr-FR", "de-DE"]

# ---------------------------------------------------------------------------
# Localized Marketing Copy & Authentic PagePilot 2.0 In-App UI Strings
# (All book titles, authors & excerpts are 100% original fictional copy.)
# ---------------------------------------------------------------------------
COPY = {
    "zh-Hans": {
        "lang": "zh-Hans",
        "slides": {
            "01_handsfree_watch": {
                "badge": "PAGEPILOT 2.0 · 解放双手",
                "title": "抬手翻页，枕边免触",
                "subtitle": "Apple Watch 轻点与旋钮隔空翻页，防误触锁屏更安心",
            },
            "02_desk_micro_reading": {
                "badge": "全新书房 · 5 分钟微阅读",
                "title": "书房归位，随时微读",
                "subtitle": "此刻书桌与精装书架一屏融合，零散片刻也能续读",
            },
            "03_paper_presets": {
                "badge": "4 组护眼纸感预设",
                "title": "四套纸感，昼夜皆宜",
                "subtitle": "晨纸、羊皮、墨水、深夜浮层直切，实时估算剩余时长",
            },
            "04_journal_postcard": {
                "badge": "印记 · 单句书摘明信片",
                "title": "阅读印记，金句成卡",
                "subtitle": "近 4 周热力日历记录节律，书摘一键生成高清暖纸明信片",
            },
            "05_ecosystem_sync": {
                "badge": "全平台协同 · 极简传书",
                "title": "多端同步，直入正文",
                "subtitle": "iPhone、iPad 与 Mac 原生适配，支持直入续读与 Wi-Fi 传书",
            },
        },
        "ui": {
            "desk_tab": "书房",
            "journal_tab": "印记",
            "today_progress": "今日已读 24 / 30 分钟",
            "watch_pill": "Watch",
            "hero_kicker": "此刻书桌",
            "continue_btn": "翻开续读",
            "micro_btn": "5 分钟微读",
            "journal_hint": "查看阅读日历与书摘 ›",
            "bookshelf": "精装书架",
            "filters": ["全部", "在读", "未读", "已读"],
            "books": [
                {"title": "晨雾与纸页", "author": "林砚舟", "progress": "42%", "pct": 42, "chapter": "第四章 · 静水微光"},
                {"title": "海风笔记本", "author": "陈听澜", "progress": "68%", "pct": 68, "chapter": "第七章 · 盐雾回廊"},
                {"title": "器物手记", "author": "沈清禾", "progress": "24%", "pct": 24, "chapter": "第二章 · 素瓷与木纹"},
                {"title": "星夜观察录", "author": "顾星辞", "progress": "85%", "pct": 85, "chapter": "第十章 · 冬季星图"},
                {"title": "南岸花园信札", "author": "周白露", "progress": "12%", "pct": 12, "chapter": "第一章 · 橄榄树影"},
            ],
            "watch_turned": "手表已翻页",
            "handsfree_unlock": "防误触中 · 点此解锁",
            "remaining_time": "约剩 12 分钟 · 42%",
            "presets": ["晨纸", "羊皮", "墨水", "深夜"],
            "dock_actions": ["目录", "外观", "朗读", "解放双手", "书签"],
            "reader_heading": "第四章　静水微光",
            "reader_p1": "清晨六点半，港口尚未完全苏醒。薄雾顺着石砌防波堤缓缓漫过水面，将远处的灯塔轮廓晕染成一笔极淡的靛青。我把热茶搁在窗边木案上，翻开昨天折起的那一页。",
            "reader_p2": "它只是安静地摊开在光线里，像一张吸饱了清晨空气的棉纸，让思绪在行距与留白之间缓慢落脚。",
            "reader_p3": "当你不再频繁抬手去碰屏幕，文字便重新恢复了纸书的分量——只剩呼吸、翻页声与窗外渐亮的天色。",
            "reader_highlight": "真正耐读的书从不急着催促读者。",
            "journal_subtitle": "阅读节律与书摘卡片盒",
            "kpi_today_val": "24 分钟",
            "kpi_today_lbl": "今日阅读 · 目标 30 分钟",
            "kpi_streak_val": "14 天",
            "kpi_streak_lbl": "连续阅读 · 18 条书摘",
            "heatmap_title": "近 4 周阅读日历",
            "full_stats": "完整统计 ›",
            "less": "少",
            "more": "多",
            "quote_box": "书摘卡片盒",
            "quote_hint": "点卡片回原文 · 点明信片分享",
            "postcard_btn": "明信片",
            "postcard_kicker": "EXCERPT · PAGEPILOT",
            "postcard_quote": "真正耐读的书从不急着催促读者，它只在光线与留白之间，让思绪慢慢落脚。",
            "postcard_book": "《晨雾与纸页》",
            "postcard_author": "林砚舟 · 第四章",
            "postcard_themes": ["暖纸", "墨夜", "晨光"],
            "quotes_list": [
                {"text": "真正耐读的书从不急着催促读者，它只在光线与留白之间，让思绪慢慢落脚。", "book": "晨雾与纸页 · 第四章"},
                {"text": "把日常器物摆在顺手的地方，清晨的五分钟也能成为一整天的锚点。", "book": "器物手记 · 第二章"},
                {"text": "潮水退去后，灯塔下的礁石仍留着星光折射的微温。", "book": "星夜观察录 · 第十章"},
            ],
            "settings_title": "设置",
            "settings_section_read": "阅读偏好",
            "settings_launch": "启动直入上次阅读页",
            "settings_launch_sub": "打开 App 自动回到上次停下的那一行",
            "settings_watch": "Apple Watch 翻页",
            "settings_watch_val": "已连接",
            "settings_icloud": "iCloud 云同步",
            "settings_icloud_val": "已同步",
            "settings_wifi": "Wi-Fi 传书",
            "settings_wifi_val": "局域网秒传",
            "settings_opds": "OPDS 书库",
            "settings_opds_val": "2 个书源",
            "settings_tts": "语音朗读 TTS",
            "settings_tts_val": "系统全语种",
            "formats_label": "全格式原生阅读",
            "watch_callout_title": "手表遥控翻页",
            "watch_callout_sub": "轻点 · 双指互点 · 旋转表冠",
            "mac_sidebar_section": "阅读空间",
            "mac_formats_section": "快捷导入",
            "mac_import_local": "导入本地书籍",
            "mac_sync_badge": "iCloud 进度已同步 · 42%",
        },
    },
    "en-US": {
        "lang": "en",
        "slides": {
            "01_handsfree_watch": {
                "badge": "PAGEPILOT 2.0 · HANDS-FREE",
                "title": "Turn Pages Hands-Free",
                "subtitle": "Flip with Apple Watch or Digital Crown, protected by Bedside Lock",
            },
            "02_desk_micro_reading": {
                "badge": "UNIFIED DESK · 5M MICRO READ",
                "title": "Your Calm Reading Desk",
                "subtitle": "Active book, 5-minute sessions & hardcover shelf in one quiet view",
            },
            "03_paper_presets": {
                "badge": "FOUR TACTILE PAPER PRESETS",
                "title": "Paper Craft, Day & Night",
                "subtitle": "Switch Paper, Sepia, E-Ink & Midnight right in the floating dock",
            },
            "04_journal_postcard": {
                "badge": "JOURNAL & QUOTE POSTCARDS",
                "title": "Rhythm & Quote Postcards",
                "subtitle": "4-week reading heatmap & quote box with framable editorial cards",
            },
            "05_ecosystem_sync": {
                "badge": "IPHONE · IPAD · MAC",
                "title": "In Sync Across Every Screen",
                "subtitle": "Resume straight to your last page with iCloud, Wi-Fi Transfer & OPDS",
            },
        },
        "ui": {
            "desk_tab": "Desk",
            "journal_tab": "Journal",
            "today_progress": "Read 24 / 30 min today",
            "watch_pill": "Watch",
            "hero_kicker": "CURRENTLY READING",
            "continue_btn": "Continue Reading",
            "micro_btn": "5m Micro Read",
            "journal_hint": "View rhythm & quote box ›",
            "bookshelf": "Bookshelf",
            "filters": ["All", "Reading", "Unread", "Finished"],
            "books": [
                {"title": "Morning Mist & Paper", "author": "Claire Vance", "progress": "42%", "pct": 42, "chapter": "Chapter 4 · Quiet Harbor"},
                {"title": "Harbor Breeze Notebook", "author": "Milo Mercer", "progress": "68%", "pct": 68, "chapter": "Chapter 7 · Salt Terrace"},
                {"title": "Notes on Everyday Craft", "author": "Hana Sato", "progress": "24%", "pct": 24, "chapter": "Chapter 2 · Clay & Cedar"},
                {"title": "Nocturne Field Notes", "author": "Arthur Vale", "progress": "85%", "pct": 85, "chapter": "Chapter 10 · Winter Sky"},
                {"title": "Letters from South Bay", "author": "Elena Solis", "progress": "12%", "pct": 12, "chapter": "Chapter 1 · Olive Shade"},
            ],
            "watch_turned": "Page turned via Watch",
            "handsfree_unlock": "Touch locked · Tap to unlock",
            "remaining_time": "~12 min left · 42%",
            "presets": ["Paper", "Sepia", "E-Ink", "Midnight"],
            "dock_actions": ["Contents", "Style", "Listen", "Hands-Free", "Bookmark"],
            "reader_heading": "Chapter 4 · Quiet Harbor",
            "reader_p1": "At half past six the harbor had barely begun to stir. A ribbon of pale fog drifted past the stone breakwater, softening the lighthouse into a faint indigo brushstroke against the dawn.",
            "reader_p2": "It rests open in quiet light like cotton paper, giving each thought room to settle between the margins.",
            "reader_p3": "When your hands stay still and the chrome disappears, digital pages recover the calm cadence of print—just breath, light, and the next line.",
            "reader_highlight": "A generous book never hurries its reader.",
            "journal_subtitle": "Reading rhythm & quote box",
            "kpi_today_val": "24 min",
            "kpi_today_lbl": "Today · Goal 30 min",
            "kpi_streak_val": "14 days",
            "kpi_streak_lbl": "Day streak · 18 quotes",
            "heatmap_title": "Last 4 Weeks",
            "full_stats": "Full Stats ›",
            "less": "Less",
            "more": "More",
            "quote_box": "Quote Box",
            "quote_hint": "Tap to open · Sparkles for postcard",
            "postcard_btn": "Postcard",
            "postcard_kicker": "EXCERPT · PAGEPILOT",
            "postcard_quote": "A generous book never hurries its reader; it waits quietly between light and margin until the mind settles.",
            "postcard_book": "Morning Mist & Paper",
            "postcard_author": "Claire Vance · Chapter 4",
            "postcard_themes": ["Paper", "Midnight", "Dawn"],
            "quotes_list": [
                {"text": "A generous book never hurries its reader; it waits quietly between light and margin.", "book": "Morning Mist & Paper · Ch. 4"},
                {"text": "Keep a single quiet ritual at dawn, and five minutes becomes an anchor for the day.", "book": "Notes on Everyday Craft · Ch. 2"},
                {"text": "Long after tide recedes, the dark stones still hold the faint warmth of starlight.", "book": "Nocturne Field Notes · Ch. 10"},
            ],
            "settings_title": "Settings",
            "settings_section_read": "READING FLOW",
            "settings_launch": "Resume Book on Launch",
            "settings_launch_sub": "Open straight to your last-read page",
            "settings_watch": "Apple Watch Control",
            "settings_watch_val": "Connected",
            "settings_icloud": "iCloud Sync",
            "settings_icloud_val": "Up to date",
            "settings_wifi": "Wi-Fi Transfer",
            "settings_wifi_val": "Browser drop",
            "settings_opds": "OPDS Catalogs",
            "settings_opds_val": "2 catalogs",
            "settings_tts": "Read Aloud (TTS)",
            "settings_tts_val": "System voices",
            "formats_label": "EVERY FORMAT READY",
            "watch_callout_title": "Apple Watch Remote",
            "watch_callout_sub": "Tap · Double Tap · Digital Crown",
            "mac_sidebar_section": "SPACES",
            "mac_formats_section": "LIBRARY",
            "mac_import_local": "Import Books",
            "mac_sync_badge": "iCloud synced · 42%",
        },
    },
    "es-ES": {
        "lang": "es",
        "slides": {
            "01_handsfree_watch": {
                "badge": "PAGEPILOT 2.0 · MANOS LIBRES",
                "title": "Pasa páginas sin tocar",
                "subtitle": "Controla con tu Apple Watch y lee tranquilo con bloqueo nocturno",
            },
            "02_desk_micro_reading": {
                "badge": "ESTUDIO UNIFICADO · 5 MIN EXPRÉS",
                "title": "Tu estudio de lectura",
                "subtitle": "Lectura actual, sesiones de 5 minutos y estantería en una vista",
            },
            "03_paper_presets": {
                "badge": "4 ESTILOS DE PAPEL CURADOS",
                "title": "Papel sereno, día y noche",
                "subtitle": "Cambia entre Papel, Sepia, Tinta E y Noche al instante",
            },
            "04_journal_postcard": {
                "badge": "DIARIO Y POSTALES DE CITA",
                "title": "Tu ritmo y tus citas",
                "subtitle": "Calendario de 4 semanas y postales editoriales para tus frases",
            },
            "05_ecosystem_sync": {
                "badge": "IPHONE · IPAD · MAC",
                "title": "Sincronizado en todo Apple",
                "subtitle": "Reanuda al abrir con iCloud, envío por Wi-Fi y todos tus formatos",
            },
        },
        "ui": {
            "desk_tab": "Estudio",
            "journal_tab": "Diario",
            "today_progress": "Hoy 24 / 30 min",
            "watch_pill": "Watch",
            "hero_kicker": "LEYENDO AHORA",
            "continue_btn": "Continuar leyendo",
            "micro_btn": "5 min exprés",
            "journal_hint": "Ver ritmo y citas ›",
            "bookshelf": "Estantería",
            "filters": ["Todo", "Leyendo", "Sin leer", "Leídos"],
            "books": [
                {"title": "Niebla y papel", "author": "Clara Miró", "progress": "42%", "pct": 42, "chapter": "Capítulo 4 · Puerto calmo"},
                {"title": "Cuaderno de brisa", "author": "Mateo Soler", "progress": "68%", "pct": 68, "chapter": "Capítulo 7 · Terraza sur"},
                {"title": "Oficios del alba", "author": "Hana Sato", "progress": "24%", "pct": 24, "chapter": "Capítulo 2 · Barro y cedro"},
                {"title": "Notas de medianoche", "author": "Arturo Vega", "progress": "85%", "pct": 85, "chapter": "Capítulo 10 · Cielo austral"},
                {"title": "Cartas del olivar", "author": "Elena Solís", "progress": "12%", "pct": 12, "chapter": "Capítulo 1 · Luz de cal"},
            ],
            "watch_turned": "Pasado desde Apple Watch",
            "handsfree_unlock": "Bloqueado · Toca para salir",
            "remaining_time": "~12 min restantes · 42%",
            "presets": ["Papel", "Sepia", "Tinta E", "Noche"],
            "dock_actions": ["Índice", "Aspecto", "Escuchar", "Manos libres", "Marcador"],
            "reader_heading": "Capítulo 4 · Puerto calmo",
            "reader_p1": "A las seis y media el puerto apenas comenzaba a despertar. Una neblina suave rozaba el espigón de piedra y convertía el faro en un trazo índigo sobre el amanecer.",
            "reader_p2": "Permanece abierto bajo la luz tibia como papel de algodón, dejando espacio para que cada idea descanse.",
            "reader_p3": "Cuando dejas de tocar la pantalla y los controles desaparecen, cada página recupera la calma serena del papel impreso.",
            "reader_highlight": "Un buen libro nunca apresura a quien lo lee.",
            "journal_subtitle": "Ritmo de lectura y caja de citas",
            "kpi_today_val": "24 min",
            "kpi_today_lbl": "Hoy · Meta 30 min",
            "kpi_streak_val": "14 días",
            "kpi_streak_lbl": "Racha · 18 citas",
            "heatmap_title": "Últimas 4 semanas",
            "full_stats": "Estadísticas ›",
            "less": "Menos",
            "more": "Más",
            "quote_box": "Caja de citas",
            "quote_hint": "Toca para volver al libro",
            "postcard_btn": "Postal",
            "postcard_kicker": "CITA · PAGEPILOT",
            "postcard_quote": "Un buen libro nunca apresura; espera con calma entre la luz y los márgenes hasta serenar la mente.",
            "postcard_book": "Niebla y papel",
            "postcard_author": "Clara Miró · Capítulo 4",
            "postcard_themes": ["Papel", "Noche", "Amanecer"],
            "quotes_list": [
                {"text": "Un buen libro nunca apresura; espera con calma entre la luz y los márgenes.", "book": "Niebla y papel · Cap. 4"},
                {"text": "Cinco minutos de silencio al alba bastan para anclar todo el día.", "book": "Oficios del alba · Cap. 2"},
                {"text": "Al bajar la marea, la piedra aún conserva la tibieza tenue de las estrellas.", "book": "Notas de medianoche · Cap. 10"},
            ],
            "settings_title": "Ajustes",
            "settings_section_read": "LECTURA",
            "settings_launch": "Reanudar libro al abrir",
            "settings_launch_sub": "Abrir directamente tu última lectura",
            "settings_watch": "Control Apple Watch",
            "settings_watch_val": "Conectado",
            "settings_icloud": "Sincronización iCloud",
            "settings_icloud_val": "Al día",
            "settings_wifi": "Transferencia Wi-Fi",
            "settings_wifi_val": "Desde navegador",
            "settings_opds": "Catálogos OPDS",
            "settings_opds_val": "2 catálogos",
            "settings_tts": "Lectura en voz alta",
            "settings_tts_val": "Voces del sistema",
            "formats_label": "TODOS TUS FORMATOS",
            "watch_callout_title": "Control Apple Watch",
            "watch_callout_sub": "Toque · Doble toque · Digital Crown",
            "mac_sidebar_section": "ESPACIOS",
            "mac_formats_section": "BIBLIOTECA",
            "mac_import_local": "Importar libros",
            "mac_sync_badge": "iCloud al día · 42%",
        },
    },
    "fr-FR": {
        "lang": "fr",
        "slides": {
            "01_handsfree_watch": {
                "badge": "PAGEPILOT 2.0 · MAINS LIBRES",
                "title": "Lisez les mains libres",
                "subtitle": "Tournez les pages via Apple Watch avec verrouillage anti-touches",
            },
            "02_desk_micro_reading": {
                "badge": "BUREAU UNIFIÉ · SESSION 5 MIN",
                "title": "Votre bureau de lecture",
                "subtitle": "Livre en cours, lecture de 5 min et bibliothèque reliée réunis",
            },
            "03_paper_presets": {
                "badge": "4 STYLES DE PAPIER CALIBRÉS",
                "title": "Confort papier, jour et nuit",
                "subtitle": "Papier, Sépia, Encre E et Nuit accessibles en un geste",
            },
            "04_journal_postcard": {
                "badge": "CARNET & CARTES CITATION",
                "title": "Rythme et cartes citation",
                "subtitle": "Calendrier sur 4 semaines et cartes éditoriales prêtes à partager",
            },
            "05_ecosystem_sync": {
                "badge": "IPHONE · IPAD · MAC",
                "title": "Fluide sur tous vos écrans",
                "subtitle": "Reprise immédiate au lancement, iCloud, transfert Wi-Fi et OPDS",
            },
        },
        "ui": {
            "desk_tab": "Bureau",
            "journal_tab": "Carnet",
            "today_progress": "Lu 24 / 30 min aujourd’hui",
            "watch_pill": "Watch",
            "hero_kicker": "LECTURE EN COURS",
            "continue_btn": "Reprendre la lecture",
            "micro_btn": "Lecture 5 min",
            "journal_hint": "Voir le rythme et les citations ›",
            "bookshelf": "Bibliothèque",
            "filters": ["Tout", "En cours", "Non lus", "Terminés"],
            "books": [
                {"title": "Brume et papier", "author": "Claire Valois", "progress": "42%", "pct": 42, "chapter": "Chapitre 4 · Port calme"},
                {"title": "Carnet de brise", "author": "Milo Delacroix", "progress": "68%", "pct": 68, "chapter": "Chapitre 7 · Terrasse sud"},
                {"title": "Notes d’atelier", "author": "Hana Sato", "progress": "24%", "pct": 24, "chapter": "Chapitre 2 · Grès et cèdre"},
                {"title": "Veilles nocturnes", "author": "Arthur Doré", "progress": "85%", "pct": 85, "chapter": "Chapitre 10 · Ciel d’hiver"},
                {"title": "Lettres d’oliveraie", "author": "Éléna Solis", "progress": "12%", "pct": 12, "chapter": "Chapitre 1 · Ombre claire"},
            ],
            "watch_turned": "Page tournée via Watch",
            "handsfree_unlock": "Verrouillé · Toucher",
            "remaining_time": "~12 min restantes · 42%",
            "presets": ["Papier", "Sépia", "Encre E", "Nuit"],
            "dock_actions": ["Sommaire", "Style", "Audio", "Mains libres", "Signet"],
            "reader_heading": "Chapitre 4 · Port calme",
            "reader_p1": "À six heures et demie, le port s’éveillait à peine. Une brume légère glissait le long de la jetée de pierre, estompant la silhouette du phare dans une teinte indigo très douce.",
            "reader_p2": "Il repose ouvert dans la lumière du matin tel un papier coton, offrant à chaque pensée un espace de silence.",
            "reader_p3": "Lorsque vos mains restent libres et que l’interface s’efface, la lecture retrouve toute la sérénité d’un ouvrage imprimé.",
            "reader_highlight": "Un grand livre ne presse jamais son lecteur.",
            "journal_subtitle": "Rythme de lecture et citations",
            "kpi_today_val": "24 min",
            "kpi_today_lbl": "Aujourd’hui · Objectif 30 min",
            "kpi_streak_val": "14 jours",
            "kpi_streak_lbl": "Série · 18 citations",
            "heatmap_title": "4 dernières semaines",
            "full_stats": "Statistiques ›",
            "less": "Moins",
            "more": "Plus",
            "quote_box": "Boîte à citations",
            "quote_hint": "Touchez pour ouvrir le passage",
            "postcard_btn": "Carte",
            "postcard_kicker": "EXTRAIT · PAGEPILOT",
            "postcard_quote": "Un grand livre ne presse jamais ; il attend paisiblement entre lumière et marges que l’esprit s’apaise.",
            "postcard_book": "Brume et papier",
            "postcard_author": "Claire Valois · Chapitre 4",
            "postcard_themes": ["Papier", "Minuit", "Aube"],
            "quotes_list": [
                {"text": "Un grand livre ne presse jamais ; il attend paisiblement entre lumière et marges.", "book": "Brume et papier · Ch. 4"},
                {"text": "Cinq minutes calmes à l’aube suffisent à donner son tempo à toute la journée.", "book": "Notes d’atelier · Ch. 2"},
                {"text": "Quand la marée descend, la roche garde encore la lueur douce des étoiles.", "book": "Veilles nocturnes · Ch. 10"},
            ],
            "settings_title": "Réglages",
            "settings_section_read": "LECTURE",
            "settings_launch": "Reprendre au lancement",
            "settings_launch_sub": "Ouvrir directement votre dernier livre",
            "settings_watch": "Contrôle Apple Watch",
            "settings_watch_val": "Connectée",
            "settings_icloud": "Synchronisation iCloud",
            "settings_icloud_val": "À jour",
            "settings_wifi": "Transfert Wi-Fi",
            "settings_wifi_val": "Via navigateur",
            "settings_opds": "Catalogues OPDS",
            "settings_opds_val": "2 sources",
            "settings_tts": "Lecture vocale (TTS)",
            "settings_tts_val": "Voix système",
            "formats_label": "TOUS VOS FORMATS",
            "watch_callout_title": "Télécommande Watch",
            "watch_callout_sub": "Toucher · Double geste · Digital Crown",
            "mac_sidebar_section": "ESPACES",
            "mac_formats_section": "BIBLIOTHÈQUE",
            "mac_import_local": "Importer des livres",
            "mac_sync_badge": "iCloud à jour · 42 %",
        },
    },
    "de-DE": {
        "lang": "de",
        "slides": {
            "01_handsfree_watch": {
                "badge": "PAGEPILOT 2.0 · FREIHAND",
                "title": "Freihändig umblättern",
                "subtitle": "Per Apple Watch & Digital Crown blättern – geschützt im Bettmodus",
            },
            "02_desk_micro_reading": {
                "badge": "LESETISCH · 5-MIN.-FOKUS",
                "title": "Dein ruhiger Lesetisch",
                "subtitle": "Aktuelles Buch, 5-Min.-Fokus und Bücherregal in einer Ansicht",
            },
            "03_paper_presets": {
                "badge": "4 KURATIERTE PAPIERSTILE",
                "title": "Papiergefühl, Tag & Nacht",
                "subtitle": "Papier, Sepia, E-Ink und Nacht direkt im Reader wechseln",
            },
            "04_journal_postcard": {
                "badge": "JOURNAL & ZITAT-POSTKARTEN",
                "title": "Rhythmus & Zitatkarten",
                "subtitle": "4-Wochen-Heatmap und edle Zitat-Postkarten aus jeder Markierung",
            },
            "05_ecosystem_sync": {
                "badge": "IPHONE · IPAD · MAC",
                "title": "Synchron auf jedem Gerät",
                "subtitle": "Direkt weiterlesen mit iCloud-Sync, WLAN-Übertragung & OPDS",
            },
        },
        "ui": {
            "desk_tab": "Lesetisch",
            "journal_tab": "Journal",
            "today_progress": "Heute 24 / 30 Min.",
            "watch_pill": "Watch",
            "hero_kicker": "AKTUELLES BUCH",
            "continue_btn": "Weiterlesen",
            "micro_btn": "5 Min. Fokus",
            "journal_hint": "Rhythmus & Zitate ansehen ›",
            "bookshelf": "Bücherregal",
            "filters": ["Alle", "Aktiv", "Ungelesen", "Fertig"],
            "books": [
                {"title": "Morgennebel & Papier", "author": "Klara Lindner", "progress": "42%", "pct": 42, "chapter": "Kapitel 4 · Stiller Hafen"},
                {"title": "Hafenbrise Notizen", "author": "Milo Berger", "progress": "68%", "pct": 68, "chapter": "Kapitel 7 · Südterrasse"},
                {"title": "Alltagsdinge", "author": "Hana Sato", "progress": "24%", "pct": 24, "chapter": "Kapitel 2 · Ton & Zeder"},
                {"title": "Nachtbeobachtungen", "author": "Arthur Stern", "progress": "85%", "pct": 85, "chapter": "Kapitel 10 · Winterhimmel"},
                {"title": "Briefe vom Olivenhang", "author": "Elena Solis", "progress": "12%", "pct": 12, "chapter": "Kapitel 1 · Kalksteinlicht"},
            ],
            "watch_turned": "Mit Watch geblättert",
            "handsfree_unlock": "Gesperrt · Tippen",
            "remaining_time": "Noch ca. 12 Min. · 42%",
            "presets": ["Papier", "Sepia", "E-Ink", "Nacht"],
            "dock_actions": ["Inhalt", "Stil", "Vorlesen", "Freihand", "Zeichen"],
            "reader_heading": "Kapitel 4 · Stiller Hafen",
            "reader_p1": "Um halb sieben erwachte der Hafen kaum merklich. Ein Schleier aus frühem Nebel zog an der Steinmole vorbei und zeichnete den Leuchtturm in sanftes Indigoblau.",
            "reader_p2": "Es liegt still im Morgenlicht wie feines Baumwollpapier und lässt jedem Gedanken Raum zwischen den Zeilen.",
            "reader_p3": "Wenn deine Hände frei bleiben und alle Bedienelemente weichen, gewinnt das Lesen die stille Tiefe gedruckter Seiten zurück.",
            "reader_highlight": "Ein gutes Buch drängt seine Leser nie.",
            "journal_subtitle": "Leserhythmus & Zitatebox",
            "kpi_today_val": "24 Min.",
            "kpi_today_lbl": "Heute · Ziel 30 Min.",
            "kpi_streak_val": "14 Tage",
            "kpi_streak_lbl": "Serie · 18 Zitate",
            "heatmap_title": "Letzte 4 Wochen",
            "full_stats": "Statistiken ›",
            "less": "Weniger",
            "more": "Mehr",
            "quote_box": "Zitatebox",
            "quote_hint": "Tippen zum Öffnen im Buch",
            "postcard_btn": "Postkarte",
            "postcard_kicker": "ZITAT · PAGEPILOT",
            "postcard_quote": "Ein gutes Buch drängt nie; es wartet ruhig zwischen Licht und Seitenrand, bis die Gedanken ankommen.",
            "postcard_book": "Morgennebel & Papier",
            "postcard_author": "Klara Lindner · Kapitel 4",
            "postcard_themes": ["Papier", "Nacht", "Morgenrot"],
            "quotes_list": [
                {"text": "Ein gutes Buch drängt nie; es wartet ruhig zwischen Licht und Seitenrand.", "book": "Morgennebel & Papier · Kap. 4"},
                {"text": "Fünf ruhige Minuten am Morgen geben dem ganzen Tag einen verlässlichen Anker.", "book": "Alltagsdinge · Kap. 2"},
                {"text": "Wenn die Flut weicht, hält der dunkle Stein noch den milden Glanz der Sterne.", "book": "Nachtbeobachtungen · Kap. 10"},
            ],
            "settings_title": "Einstellungen",
            "settings_section_read": "LESEFLUSS",
            "settings_launch": "Beim Start direkt weiterlesen",
            "settings_launch_sub": "Öffnet sofort das zuletzt gelesene Buch",
            "settings_watch": "Apple Watch Steuerung",
            "settings_watch_val": "Verbunden",
            "settings_icloud": "iCloud-Sync",
            "settings_icloud_val": "Aktuell",
            "settings_wifi": "WLAN-Übertragung",
            "settings_wifi_val": "Per Browser",
            "settings_opds": "OPDS-Kataloge",
            "settings_opds_val": "2 Quellen",
            "settings_tts": "Vorlesen (TTS)",
            "settings_tts_val": "Systemstimmen",
            "formats_label": "ALLE FORMATE BEREIT",
            "watch_callout_title": "Apple Watch Fernsteuerung",
            "watch_callout_sub": "Tippen · Doppeltipp · Digital Crown",
            "mac_sidebar_section": "BEREICHE",
            "mac_formats_section": "BIBLIOTHEK",
            "mac_import_local": "Bücher importieren",
            "mac_sync_badge": "iCloud aktuell · 42 %",
        },
    },
}


def file_data_uri(path: Path) -> str:
    ext = path.suffix.lower()
    mime = "image/png" if ext == ".png" else "image/jpeg"
    data = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{data}"


def cover_data_uri(path: Path, trim_margin: bool = False) -> str:
    if not trim_margin:
        return file_data_uri(path)
    import io
    im = Image.open(path).convert("RGB")
    w, h = im.size
    dx, dy = int(w * 0.075), int(h * 0.065)
    cropped = im.crop((dx, dy, w - dx, h - dy))
    buf = io.BytesIO()
    cropped.save(buf, format="JPEG", quality=92)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def discover_assets():
    landscape = sorted((ART_DIR / "landscape").glob("*.[jp][pn]g"))
    covers_dir = ART_DIR / "covers"
    gen_covers = sorted(covers_dir.glob("*.[jp][pn]g")) if covers_dir.exists() else []

    dark_land = None
    warm_land = None
    cool_land = None
    for p in landscape:
        im = Image.open(p).convert("RGB").resize((32, 32))
        px = list(im.get_flattened_data()) if hasattr(im, "get_flattened_data") else list(im.getdata())
        avg_r = sum(c[0] for c in px) / len(px)
        avg_g = sum(c[1] for c in px) / len(px)
        avg_b = sum(c[2] for c in px) / len(px)
        lum = 0.299 * avg_r + 0.587 * avg_g + 0.114 * avg_b
        if lum < 135:
            dark_land = p
        elif avg_r > avg_b + 10:
            warm_land = p
        else:
            cool_land = p

    p_dark = ART_DIR / "portrait" / "prompt_0_0.jpg"
    p_warm = ART_DIR / "portrait" / "prompt_1_0.jpg"
    p_cool = ART_DIR / "portrait" / "prompt_2_0.jpg"

    l_dark = dark_land or (landscape[0] if landscape else p_dark)
    l_warm = warm_land or p_warm
    l_cool = cool_land or p_cool

    covers = [SAMPLE_COVER] + gen_covers
    while len(covers) < 5:
        covers.append(SAMPLE_COVER)

    watch_map = {}
    for loc in LOCALES:
        wp = WATCH_DIR / loc / "02_turn_page.png"
        if not wp.exists():
            wp = WATCH_DIR / "en-US" / "02_turn_page.png"
        watch_map[loc] = file_data_uri(wp)

    cover_uris = []
    for c in covers[:5]:
        # prompt_2_0.jpg (observatory night cover) has a thin white paper margin — trim cleanly
        trim = c.name == "prompt_2_0.jpg"
        cover_uris.append(cover_data_uri(c, trim_margin=trim))

    return {
        "portrait": {
            "dark": file_data_uri(p_dark),
            "warm": file_data_uri(p_warm),
            "cool": file_data_uri(p_cool),
        },
        "landscape": {
            "dark": file_data_uri(l_dark),
            "warm": file_data_uri(l_warm),
            "cool": file_data_uri(l_cool),
        },
        "covers": cover_uris,
        "app_icon": file_data_uri(APP_ICON),
        "watch": watch_map,
    }


def esc(s: str) -> str:
    return html.escape(s, quote=True)


# ---------------------------------------------------------------------------
# SVG Icons (clean SF-Symbol inspired stroke vectors)
# ---------------------------------------------------------------------------
ICO_BOOK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20"/></svg>'
ICO_JOURNAL = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="3"/><path d="M8 2v4M16 2v4M3 10h18M8 14h4M8 18h8"/></svg>'
ICO_WATCH = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="6" width="12" height="12" rx="3"/><path d="M9 6V3h6v3M9 18v3h6v-3M18 10h1.5"/></svg>'
ICO_LOCK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>'
ICO_SPARKLE = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.1 6.2L20 10l-5.9 1.8L12 18l-2.1-6.2L4 10l5.9-1.8L12 2zm7 13l1.1 3 3 1.1-3 1.1-1.1 3-1.1-3-3-1.1 3-1.1 1.1-3z"/></svg>'
ICO_GEAR = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.6.85 1 1.51 1H21a2 2 0 1 1 0 4h-.09c-.66 0-1.25.4-1.51 1z"/></svg>'
ICO_PLUS = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>'
ICO_TIMER = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M9 2h6"/></svg>'
ICO_CLOUD = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M18 10h-1.26A8 8 0 1 0 9 20h9a5 5 0 0 0 0-10z"/></svg>'
ICO_WIFI = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.55a11 11 0 0 1 14.08 0M1.42 9a16 16 0 0 1 21.16 0M8.53 16.11a6 6 0 0 1 6.95 0M12 20h.01"/></svg>'
ICO_LIST = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M4 6h16M4 12h16M4 18h10"/></svg>'
ICO_HEADPHONES = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M3 18v-6a9 9 0 0 1 18 0v6"/><path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z"/></svg>'
ICO_BOOKMARK = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/></svg>'
ICO_PLAY = '<svg viewBox="0 0 24 24" fill="currentColor"><polygon points="6,4 20,12 6,20"/></svg>'


# ---------------------------------------------------------------------------
# Reusable UI Component Builders
# ---------------------------------------------------------------------------
def status_bar_html(dark_text=True, is_ipad=False):
    cls = "status-bar dark-ink" if dark_text else "status-bar light-ink"
    if is_ipad:
        return f"""
        <div class="{cls} ipad-sb">
          <span>9:41</span>
          <div class="sb-right">
            <span class="sb-wifi"></span>
            <span class="sb-battery"><span></span></span>
          </div>
        </div>"""
    return f"""
    <div class="{cls}">
      <span class="sb-time">9:41</span>
      <div class="dynamic-island"></div>
      <div class="sb-right">
        <span class="sb-bars"><i></i><i></i><i></i><i></i></span>
        <span class="sb-battery"><span></span></span>
      </div>
    </div>"""


def tab_bar_html(ui, active="desk"):
    d_cls = "tab-item active" if active == "desk" else "tab-item"
    j_cls = "tab-item active" if active == "journal" else "tab-item"
    return f"""
    <div class="ios-tabbar">
      <div class="{d_cls}">{ICO_BOOK}<span>{esc(ui['desk_tab'])}</span></div>
      <div class="{j_cls}">{ICO_JOURNAL}<span>{esc(ui['journal_tab'])}</span></div>
    </div>"""


def sidebar_html(ui, active="desk", is_mac=False):
    d_cls = "sb-nav-item active" if active == "desk" else "sb-nav-item"
    j_cls = "sb-nav-item active" if active == "journal" else "sb-nav-item"
    extra = ""
    if is_mac:
        extra = f"""
        <div class="sb-section-lbl">{esc(ui['mac_formats_section'])}</div>
        <div class="sb-nav-item subtle">{ICO_PLUS}<span>{esc(ui['mac_import_local'])}</span></div>
        <div class="sb-nav-item subtle">{ICO_WIFI}<span>{esc(ui['settings_wifi'])}</span></div>
        <div class="sb-nav-item subtle">{ICO_CLOUD}<span>{esc(ui['settings_icloud'])}</span></div>
        """
    return f"""
    <aside class="app-sidebar {'mac-sb' if is_mac else 'ipad-sidebar'}">
      <div class="sb-brand">
        <span class="sb-brand-dot"></span>
        <span>PagePilot</span>
      </div>
      <div class="sb-section-lbl">{esc(ui['mac_sidebar_section'])}</div>
      <div class="{d_cls}">{ICO_BOOK}<span>{esc(ui['desk_tab'])}</span></div>
      <div class="{j_cls}">{ICO_JOURNAL}<span>{esc(ui['journal_tab'])}</span></div>
      {extra}
      <div class="sb-footer-pill">
        <span class="green-dot"></span>
        <span>{esc(ui['watch_pill'])} · {esc(ui['settings_watch_val'])}</span>
      </div>
    </aside>"""


def screen_handsfree_reader(ui, family="iphone"):
    is_mac = family == "mac"
    is_ipad = family == "ipad"
    sb = "" if is_mac else status_bar_html(dark_text=True, is_ipad=is_ipad)
    book = ui["books"][0]
    p3_block = f"<p>{esc(ui['reader_p3'])}</p>" if family != "iphone" else f"<p>{esc(ui['reader_p3'])}</p>"
    return f"""
    <div class="screen reader-sepia-screen {'mac-reader-canvas' if is_mac else ''}">
      {sb}
      <div class="watch-turned-pill">
        <span class="wt-ico">{ICO_WATCH}</span>
        <span>{esc(ui['watch_turned'])}</span>
      </div>
      <div class="reader-page {'wide-page' if family != 'iphone' else ''}">
        <div class="reader-running-head">{esc(book['title'])}</div>
        <h3 class="reader-chapter-title">{esc(ui['reader_heading'])}</h3>
        <p>{esc(ui['reader_p1'])}</p>
        <p>{esc(ui['reader_highlight'])} {esc(ui['reader_p2'])}</p>
        {p3_block}
      </div>
      <div class="handsfree-unlock-pill">
        <span class="hf-lock">{ICO_LOCK}</span>
        <span>{esc(ui['handsfree_unlock'])}</span>
      </div>
      <div class="hairline-progress"><div class="hairline-fill" style="width:42%"></div></div>
    </div>"""


def screen_desk(ui, assets, family="iphone"):
    is_mac = family == "mac"
    is_ipad = family == "ipad"
    book0 = ui["books"][0]
    cols = 3 if family == "iphone" else (5 if family == "mac" else 3)
    shelf_books = ui["books"][:5]
    covers = assets["covers"]
    cards_html = []
    for idx, b in enumerate(shelf_books):
        cards_html.append(
            f"""
            <div class="shelf-card">
              <div class="cover-wrap">
                <img src="{covers[idx]}" alt="">
                <div class="spine-crease"></div>
                <div class="cover-badge">{esc(b['progress'])}</div>
              </div>
              <div class="book-title">{esc(b['title'])}</div>
              <div class="book-author">{esc(b['author'])}</div>
            </div>"""
        )
    if family in ("iphone", "ipad"):
        cards_html.append(
            f"""
            <div class="shelf-card">
              <div class="cover-wrap import-tile">
                <div class="import-plus">{ICO_PLUS}</div>
                <div class="import-lbl">{esc(ui['mac_import_local'])}</div>
              </div>
            </div>"""
        )
    filters_html = "".join(
        f'<span class="filter-chip {"active" if i == 0 else ""}">{esc(f)}</span>'
        for i, f in enumerate(ui["filters"])
    )

    body = f"""
    <div class="desk-main">
      <div class="desk-top-row">
        <div>
          <div class="desk-page-title">{esc(ui['desk_tab'])}</div>
          <div class="desk-progress-sub">{esc(ui['today_progress'])}</div>
        </div>
        <div class="desk-top-actions">
          <span class="watch-status-pill"><span class="green-dot"></span>{esc(ui['watch_pill'])}</span>
          <span class="icon-circle">{ICO_PLUS}</span>
          <span class="icon-circle">{ICO_GEAR}</span>
        </div>
      </div>

      <div class="hero-reading-card">
        <div class="hero-cover-wrap">
          <img src="{covers[0]}" alt="">
          <div class="spine-crease"></div>
        </div>
        <div class="hero-info">
          <div class="hero-kicker">{esc(ui['hero_kicker'])}</div>
          <div class="hero-book-title">{esc(book0['title'])}</div>
          <div class="hero-book-meta">{esc(book0['author'])} · {esc(book0['chapter'])}</div>
          <div class="hero-prog-row">
            <div class="hero-prog-track"><div class="hero-prog-fill" style="width:42%"></div></div>
            <span class="hero-prog-pct">42%</span>
          </div>
          <div class="hero-cta-row">
            <div class="cta-primary">{ICO_PLAY}<span>{esc(ui['continue_btn'])}</span></div>
            <div class="cta-secondary">{ICO_TIMER}<span>{esc(ui['micro_btn'])}</span></div>
          </div>
        </div>
      </div>

      <div class="shelf-header-row">
        <div class="shelf-title">{esc(ui['bookshelf'])}</div>
        <div class="filter-row">{filters_html}</div>
      </div>

      <div class="shelf-grid cols-{cols}">
        {''.join(cards_html)}
      </div>
    </div>"""

    if is_mac or is_ipad:
        sb_top = "" if is_mac else status_bar_html(dark_text=True, is_ipad=True)
        return f"""
        <div class="screen app-bg split-screen">
          {sb_top}
          <div class="split-body">
            {sidebar_html(ui, active="desk", is_mac=is_mac)}
            {body}
          </div>
        </div>"""
    return f"""
    <div class="screen app-bg">
      {status_bar_html(dark_text=True, is_ipad=False)}
      {body}
      {tab_bar_html(ui, active="desk")}
    </div>"""


def screen_paper_presets(ui, family="iphone"):
    is_mac = family == "mac"
    is_ipad = family == "ipad"
    book0 = ui["books"][0]
    sb = "" if is_mac else status_bar_html(dark_text=True, is_ipad=is_ipad)
    preset_styles = [
        ("paper", "#FAF8F4", "#1F2329", False),
        ("sepia", "#F4ECD8", "#433422", True),
        ("eink", "#FFFFFF", "#111111", False),
        ("night", "#121316", "#EBEDF2", False),
    ]
    preset_pills = []
    for idx, (_, bg, fg, active) in enumerate(preset_styles):
        ring = "active" if active else ""
        preset_pills.append(
            f'<div class="preset-chip {ring}"><span class="swatch" style="background:{bg};color:{fg}">Aa</span><span>{esc(ui["presets"][idx])}</span></div>'
        )
    dock_icons = [ICO_LIST, '<span class="aa-glyph">Aa</span>', ICO_HEADPHONES, ICO_LOCK, ICO_BOOKMARK]
    dock_btns = "".join(
        f'<div class="dock-btn {"active-teal" if i == 3 else ""}">{dock_icons[i]}<span>{esc(lbl)}</span></div>'
        for i, lbl in enumerate(ui["dock_actions"])
    )

    mac_toolbar = ""
    if is_mac:
        mac_toolbar = f"""
        <div class="mac-reader-toolbar">
          <div class="mrt-left">
            <span class="mrt-chip">{ICO_LIST}<span>{esc(ui['dock_actions'][0])}</span></span>
            <span class="mrt-title">{esc(book0['title'])}</span>
          </div>
          <div class="mrt-right">
            <div class="mrt-presets">{''.join(preset_pills)}</div>
            <span class="mrt-chip teal">{ICO_LOCK}<span>{esc(ui['dock_actions'][3])}</span><kbd>⌘⇧L</kbd></span>
            <span class="mrt-chip">{ICO_HEADPHONES}</span>
          </div>
        </div>"""

    return f"""
    <div class="screen reader-morning-screen">
      {sb}
      {mac_toolbar}
      <div class="reader-top-chrome {'hide' if is_mac else ''}">
        <span class="rtc-back">‹ {esc(ui['desk_tab'])}</span>
        <span class="rtc-title">{esc(book0['title'])}</span>
        <span class="rtc-mark">{ICO_BOOKMARK}</span>
      </div>
      <div class="reader-page morning-page {'wide-page' if family != 'iphone' else ''}">
        <h3 class="reader-chapter-title">{esc(ui['reader_heading'])}</h3>
        <p>{esc(ui['reader_p1'])}</p>
        <p><span class="text-highlight">{esc(ui['reader_highlight'])}</span> {esc(ui['reader_p2'])}</p>
        <p>{esc(ui['reader_p3'])}</p>
      </div>
      {"" if is_mac else f'''
      <div class="reader-floating-dock">
        <div class="dock-top-meta">
          <div class="dock-presets-row">{"".join(preset_pills)}</div>
          <div class="dock-rem-time">{esc(ui['remaining_time'])}</div>
        </div>
        <div class="dock-slider"><div class="dock-slider-fill" style="width:42%"></div><div class="dock-slider-knob" style="left:42%"></div></div>
        <div class="dock-actions-row">{dock_btns}</div>
      </div>'''}
      {f'<div class="mac-reader-footer"><span>{esc(book0["chapter"])}</span><span>{esc(ui["remaining_time"])}</span></div>' if is_mac else ''}
    </div>"""


def screen_journal(ui, family="iphone"):
    is_mac = family == "mac"
    is_ipad = family == "ipad"
    # Organic 28-day heatmap intensity pattern (0..4)
    heat_levels = [
        1, 2, 0, 3, 2, 4, 3,
        2, 3, 2, 1, 3, 4, 2,
        0, 2, 3, 4, 3, 2, 3,
        2, 3, 4, 3, 4, 2, 4,
    ]
    cells = "".join(f'<span class="hm-cell lv-{lv}"></span>' for lv in heat_levels)
    quotes_html = []
    colors = ["#299E94", "#386EF2", "#C9893A"]
    for idx, q in enumerate(ui["quotes_list"][:3]):
        quotes_html.append(
            f"""
            <div class="quote-row-card">
              <span class="quote-accent-bar" style="background:{colors[idx]}"></span>
              <div class="quote-row-body">
                <div class="quote-row-text">“{esc(q['text'])}”</div>
                <div class="quote-row-foot">
                  <span>{esc(q['book'])}</span>
                  <span class="postcard-mini-btn">{ICO_SPARKLE}<span>{esc(ui['postcard_btn'])}</span></span>
                </div>
              </div>
            </div>"""
        )

    body = f"""
    <div class="journal-main">
      <div class="desk-top-row">
        <div>
          <div class="desk-page-title">{esc(ui['journal_tab'])}</div>
          <div class="desk-progress-sub">{esc(ui['journal_subtitle'])}</div>
        </div>
        <div class="desk-top-actions">
          <span class="icon-circle">{ICO_GEAR}</span>
        </div>
      </div>

      <div class="kpi-duo">
        <div class="kpi-card">
          <div class="kpi-top">
            <div class="kpi-val">{esc(ui['kpi_today_val'])}</div>
            <div class="kpi-ring"><span>80%</span></div>
          </div>
          <div class="kpi-lbl">{esc(ui['kpi_today_lbl'])}</div>
        </div>
        <div class="kpi-card">
          <div class="kpi-top">
            <div class="kpi-val teal-val">{esc(ui['kpi_streak_val'])}</div>
            <span class="streak-flame">✦</span>
          </div>
          <div class="kpi-lbl">{esc(ui['kpi_streak_lbl'])}</div>
        </div>
      </div>

      <div class="heatmap-card">
        <div class="hm-head">
          <span class="hm-title">{esc(ui['heatmap_title'])}</span>
          <span class="hm-link">{esc(ui['full_stats'])}</span>
        </div>
        <div class="hm-grid">{cells}</div>
        <div class="hm-legend">
          <span>{esc(ui['less'])}</span>
          <span class="hm-cell lv-0"></span>
          <span class="hm-cell lv-1"></span>
          <span class="hm-cell lv-2"></span>
          <span class="hm-cell lv-3"></span>
          <span class="hm-cell lv-4"></span>
          <span>{esc(ui['more'])}</span>
        </div>
      </div>

      <div class="quote-section-head">
        <span class="shelf-title">{esc(ui['quote_box'])}</span>
        <span class="quote-hint">{esc(ui['quote_hint'])}</span>
      </div>
      <div class="quote-list">{''.join(quotes_html)}</div>
    </div>"""

    if is_mac or is_ipad:
        sb_top = "" if is_mac else status_bar_html(dark_text=True, is_ipad=True)
        return f"""
        <div class="screen app-bg split-screen">
          {sb_top}
          <div class="split-body">
            {sidebar_html(ui, active="journal", is_mac=is_mac)}
            {body}
          </div>
        </div>"""
    return f"""
    <div class="screen app-bg">
      {status_bar_html(dark_text=True, is_ipad=False)}
      {body}
      {tab_bar_html(ui, active="journal")}
    </div>"""


def screen_settings_sync(ui, assets, family="iphone"):
    is_ipad = family == "ipad"
    sb = status_bar_html(dark_text=True, is_ipad=is_ipad)
    rows = [
        (ICO_WATCH, "#299E94", ui["settings_watch"], ui["settings_watch_val"], True),
        (ICO_CLOUD, "#386EF2", ui["settings_icloud"], ui["settings_icloud_val"], True),
        (ICO_WIFI, "#5E6AD2", ui["settings_wifi"], ui["settings_wifi_val"], False),
        (ICO_BOOK, "#D97736", ui["settings_opds"], ui["settings_opds_val"], False),
        (ICO_HEADPHONES, "#0E8A7E", ui["settings_tts"], ui["settings_tts_val"], False),
    ]
    rows_html = []
    for ico, color, title, val, green in rows:
        badge_cls = "row-val-green" if green else "row-val"
        rows_html.append(
            f"""
            <div class="set-row">
              <span class="set-ico" style="background:{color}">{ico}</span>
              <span class="set-name">{esc(title)}</span>
              <span class="{badge_cls}">{esc(val)}</span>
              <span class="set-chev">›</span>
            </div>"""
        )

    formats = ["EPUB", "PDF", "Markdown", "TXT", "Audio", "CBZ"]
    fmt_pills = "".join(f'<span class="fmt-pill">{f}</span>' for f in formats)

    return f"""
    <div class="screen app-bg settings-screen">
      {sb}
      <div class="settings-main">
        <div class="settings-header">
          <div class="app-badge-row">
            <img class="mini-app-icon" src="{assets['app_icon']}" alt="">
            <div>
              <div class="settings-title">{esc(ui['settings_title'])}</div>
              <div class="settings-sub">PagePilot 2.0 · iCloud Sync</div>
            </div>
          </div>
        </div>

        <div class="set-section-lbl">{esc(ui['settings_section_read'])}</div>
        <div class="set-card highlight-toggle-card">
          <div class="toggle-row">
            <div class="toggle-copy">
              <div class="toggle-title">{esc(ui['settings_launch'])}</div>
              <div class="toggle-sub">{esc(ui['settings_launch_sub'])}</div>
            </div>
            <div class="ios-switch on"><span></span></div>
          </div>
        </div>

        <div class="set-card list-card">
          {''.join(rows_html)}
        </div>

        <div class="formats-card">
          <div class="fmt-head">{esc(ui['formats_label'])}</div>
          <div class="fmt-row">{fmt_pills}</div>
        </div>

        <div class="sync-status-card">
          <div class="sync-card-top">
            <span class="green-dot"></span>
            <span class="sync-card-title">{esc(ui['mac_sync_badge'])}</span>
          </div>
          <div class="sync-devices-row">
            <div class="sync-dev-chip"><span>iPhone</span><i>✓</i></div>
            <div class="sync-dev-chip"><span>iPad</span><i>✓</i></div>
            <div class="sync-dev-chip"><span>Mac</span><i>✓</i></div>
            <div class="sync-dev-chip"><span>Watch</span><i>✓</i></div>
          </div>
        </div>
      </div>
    </div>"""


def floating_watch_html(ui, watch_uri, compact=False):
    cls = "watch-float compact" if compact else "watch-float"
    return f"""
    <div class="{cls}">
      <div class="watch-pulse-ring"></div>
      <div class="watch-crown"></div>
      <div class="watch-side-btn"></div>
      <div class="watch-bezel">
        <div class="watch-glass">
          <img src="{watch_uri}" alt="Apple Watch">
        </div>
      </div>
      <div class="watch-caption-pill">
        <span class="green-dot"></span>
        <span>{esc(ui['watch_callout_sub'])}</span>
      </div>
    </div>"""


def floating_postcard_html(ui, compact=False):
    cls = "postcard-float compact" if compact else "postcard-float"
    themes = ui["postcard_themes"]
    return f"""
    <div class="{cls}">
      <div class="pc-kicker">{esc(ui['postcard_kicker'])}</div>
      <div class="pc-mark">“</div>
      <div class="pc-quote">{esc(ui['postcard_quote'])}</div>
      <div class="pc-divider"></div>
      <div class="pc-footer">
        <div>
          <div class="pc-book">{esc(ui['postcard_book'])}</div>
          <div class="pc-author">{esc(ui['postcard_author'])}</div>
        </div>
        <div class="pc-dots">
          <span class="pc-dot active" style="background:#F7F1E3" title="{esc(themes[0])}"></span>
          <span class="pc-dot" style="background:#181B22" title="{esc(themes[1])}"></span>
          <span class="pc-dot" style="background:#EAEFF8" title="{esc(themes[2])}"></span>
        </div>
      </div>
    </div>"""


def floating_presets_strip_html(ui):
    specs = [
        ("#FAF8F4", "#1F2329", ui["presets"][0], False),
        ("#F4ECD8", "#433422", ui["presets"][1], True),
        ("#FFFFFF", "#111111", ui["presets"][2], False),
        ("#121316", "#EBEDF2", ui["presets"][3], False),
    ]
    items = []
    for bg, fg, name, active in specs:
        items.append(
            f"""
            <div class="fp-chip {'active' if active else ''}">
              <span class="fp-dot" style="background:{bg};color:{fg}">Aa</span>
              <span>{esc(name)}</span>
            </div>"""
        )
    return f'<div class="floating-presets-strip">{"".join(items)}</div>'


def mac_window_wrap(inner_html, title="PagePilot", extra_cls=""):
    return f"""
    <div class="mac-window {extra_cls}">
      <div class="mac-titlebar">
        <div class="mac-lights">
          <span class="ml-r"></span><span class="ml-y"></span><span class="ml-g"></span>
        </div>
        <div class="mac-tb-title">{esc(title)}</div>
        <div class="mac-tb-spacer"></div>
      </div>
      <div class="mac-window-body">{inner_html}</div>
    </div>"""


# ---------------------------------------------------------------------------
# Full Slide HTML Assembly
# ---------------------------------------------------------------------------
def build_slide_html(locale: str, device_key: str, slide_key: str, assets: dict) -> str:
    spec = DEVICES[device_key]
    family = spec["family"]
    cw = spec["w"] // 2
    ch = spec["h"] // 2
    data = COPY[locale]
    slide_meta = data["slides"][slide_key]
    ui = data["ui"]
    watch_uri = assets["watch"][locale]

    # Backdrop & theme polarity per slide
    if slide_key in ("01_handsfree_watch", "03_paper_presets"):
        mood = "dark"
        header_theme = "light-text"
    elif slide_key in ("02_desk_micro_reading", "04_journal_postcard"):
        mood = "warm"
        header_theme = "dark-text"
    else:
        mood = "cool"
        header_theme = "dark-text"

    bg_uri = assets["landscape"][mood] if family == "mac" else assets["portrait"][mood]

    # Build Stage Content per Device Family & Slide
    if family == "mac":
        if slide_key == "01_handsfree_watch":
            stage = f"""
            <div class="mac-stage stage-watch">
              {mac_window_wrap(screen_handsfree_reader(ui, "mac"), f"{ui['books'][0]['title']} — PagePilot", "mac-win-hero")}
              {floating_watch_html(ui, watch_uri, compact=False)}
            </div>"""
        elif slide_key == "02_desk_micro_reading":
            stage = f"""
            <div class="mac-stage">
              {mac_window_wrap(screen_desk(ui, assets, "mac"), f"PagePilot — {ui['desk_tab']}", "mac-win-hero")}
            </div>"""
        elif slide_key == "03_paper_presets":
            stage = f"""
            <div class="mac-stage stage-presets">
              {mac_window_wrap(screen_paper_presets(ui, "mac"), f"{ui['books'][0]['title']} — PagePilot", "mac-win-hero")}
            </div>"""
        elif slide_key == "04_journal_postcard":
            stage = f"""
            <div class="mac-stage stage-postcard">
              {mac_window_wrap(screen_journal(ui, "mac"), f"PagePilot — {ui['journal_tab']}", "mac-win-hero")}
              {floating_postcard_html(ui, compact=False)}
            </div>"""
        else:
            # Slide 05 Mac: Dual-window Mac (Desk + Reader) + companion synced iPhone!
            stage = f"""
            <div class="mac-stage stage-ecosystem">
              {mac_window_wrap(screen_desk(ui, assets, "mac"), f"PagePilot — {ui['desk_tab']}", "mac-win-back")}
              {mac_window_wrap(screen_handsfree_reader(ui, "mac"), f"{ui['books'][0]['title']}", "mac-win-front")}
              <div class="companion-iphone">
                <div class="ci-frame">
                  {screen_settings_sync(ui, assets, "iphone")}
                </div>
              </div>
              <div class="sync-float-badge">
                <span class="green-dot"></span>
                <span>{esc(ui['mac_sync_badge'])}</span>
              </div>
            </div>"""
    else:
        # iPhone or iPad portrait stage
        frame_cls = "ipad-frame" if family == "ipad" else "iphone-frame"
        if slide_key == "01_handsfree_watch":
            inner = screen_handsfree_reader(ui, family)
            accent = floating_watch_html(ui, watch_uri, compact=(family == "iphone"))
        elif slide_key == "02_desk_micro_reading":
            inner = screen_desk(ui, assets, family)
            accent = ""
        elif slide_key == "03_paper_presets":
            inner = screen_paper_presets(ui, family)
            accent = ""
        elif slide_key == "04_journal_postcard":
            inner = screen_journal(ui, family)
            accent = floating_postcard_html(ui, compact=(family == "iphone"))
        else:
            inner = screen_settings_sync(ui, assets, family)
            accent = f"""
            <div class="eco-device-pill">
              <span>iPhone</span><i>·</i><span>iPad</span><i>·</i><span>Mac</span><i>·</i><span>Apple Watch</span>
            </div>"""

        stage = f"""
        <div class="portrait-stage stage-{slide_key}">
          <div class="{frame_cls}">
            <div class="device-screen-clip">
              {inner}
            </div>
          </div>
          {accent}
        </div>"""

    return f"""<!DOCTYPE html>
<html lang="{esc(data['lang'])}">
<head>
<meta charset="utf-8">
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  html, body {{
    width: {cw}px;
    height: {ch}px;
    overflow: hidden;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", "Hiragino Sans GB", "Helvetica Neue", sans-serif;
    -webkit-font-smoothing: antialiased;
    text-rendering: optimizeLegibility;
    font-variant-numeric: tabular-nums;
  }}

  .canvas {{
    position: relative;
    width: {cw}px;
    height: {ch}px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    align-items: center;
  }}
  .backdrop {{
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
    z-index: 0;
  }}
  .scrim {{
    position: absolute;
    inset: 0;
    z-index: 1;
  }}
  .scrim.dark {{
    background: linear-gradient(180deg, rgba(10,14,26,0.52) 0%, rgba(10,14,26,0.12) 48%, rgba(10,14,26,0.34) 100%);
  }}
  .scrim.warm {{
    background: linear-gradient(180deg, rgba(252,248,240,0.44) 0%, rgba(252,248,240,0.06) 55%, rgba(235,224,205,0.22) 100%);
  }}
  .scrim.cool {{
    background: linear-gradient(180deg, rgba(244,248,255,0.56) 0%, rgba(236,244,252,0.12) 55%, rgba(20,56,74,0.12) 100%);
  }}

  /* ---------------- Marketing Header ---------------- */
  .header {{
    position: relative;
    z-index: 5;
    width: 100%;
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }}
  .family-iphone .header {{
    padding: 58px 42px 26px;
    min-height: 292px;
  }}
  .family-ipad .header {{
    padding: 54px 86px 26px;
    min-height: 270px;
  }}
  .family-mac .header {{
    padding: 36px 90px 18px;
    min-height: 192px;
  }}

  .badge-pill {{
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 6px 16px;
    border-radius: 999px;
    font-size: 13px;
    font-weight: 700;
    letter-spacing: 0.09em;
    text-transform: uppercase;
    margin-bottom: 14px;
    backdrop-filter: blur(14px);
  }}
  .light-text .badge-pill {{
    background: rgba(255, 255, 255, 0.14);
    border: 1px solid rgba(255, 255, 255, 0.24);
    color: #F6EFE2;
  }}
  .dark-text .badge-pill {{
    background: rgba(26, 28, 36, 0.08);
    border: 1px solid rgba(26, 28, 36, 0.12);
    color: #2A4F8F;
  }}
  .badge-dot {{
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: linear-gradient(135deg, #386EF2, #299E94);
  }}

  .headline {{
    font-weight: 760;
    letter-spacing: -0.03em;
    line-height: 1.12;
    text-wrap: balance;
    max-width: 96%;
  }}
  .family-iphone .headline {{ font-size: 52px; }}
  .family-ipad .headline {{ font-size: 62px; }}
  .family-mac .headline {{ font-size: 52px; }}
  .light-text .headline {{
    color: #FDFBF7;
    text-shadow: 0 8px 30px rgba(8, 12, 24, 0.36);
  }}
  .dark-text .headline {{
    color: #161922;
  }}

  .subtitle {{
    margin-top: 12px;
    font-weight: 460;
    line-height: 1.44;
    text-wrap: balance;
    max-width: 92%;
  }}
  .family-iphone .subtitle {{ font-size: 19.5px; max-width: 93%; }}
  .family-ipad .subtitle {{ font-size: 23px; max-width: 82%; }}
  .family-mac .subtitle {{ font-size: 20.5px; margin-top: 8px; }}
  .light-text .subtitle {{ color: rgba(247, 242, 232, 0.84); }}
  .dark-text .subtitle {{ color: rgba(28, 34, 48, 0.74); }}

  /* ---------------- Device Frames ---------------- */
  .portrait-stage {{
    position: relative;
    z-index: 4;
    flex: 1;
    width: 100%;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding-top: 6px;
  }}

  .iphone-frame {{
    position: relative;
    width: 504px;
    height: 1044px;
    border-radius: 62px;
    padding: 13px;
    background: linear-gradient(145deg, #383B42 0%, #1C1E23 45%, #2D3037 100%);
    box-shadow:
      0 42px 96px rgba(8, 14, 28, 0.44),
      0 12px 30px rgba(8, 14, 28, 0.24),
      inset 0 0 0 1.5px rgba(255, 255, 255, 0.24),
      inset 0 0 0 4px rgba(0, 0, 0, 0.5);
  }}
  .ipad-frame {{
    position: relative;
    width: 836px;
    height: 1068px;
    border-radius: 40px;
    padding: 16px;
    background: linear-gradient(145deg, #34373F 0%, #191B20 48%, #2C2F36 100%);
    box-shadow:
      0 46px 104px rgba(8, 14, 28, 0.42),
      0 12px 30px rgba(8, 14, 28, 0.22),
      inset 0 0 0 1.5px rgba(255, 255, 255, 0.24),
      inset 0 0 0 4px rgba(0, 0, 0, 0.5);
  }}
  .device-screen-clip {{
    width: 100%;
    height: 100%;
    border-radius: 50px;
    overflow: hidden;
    background: #F6F8FC;
    position: relative;
  }}
  .ipad-frame .device-screen-clip {{
    border-radius: 26px;
  }}

  .screen {{
    width: 100%;
    height: 100%;
    position: relative;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }}
  .app-bg {{ background: #F6F8FC; color: #16181F; }}

  /* ---------------- Status Bar & Tab Bar ---------------- */
  .status-bar {{
    height: 46px;
    padding: 12px 26px 0;
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 14px;
    font-weight: 650;
    flex-shrink: 0;
    position: relative;
    z-index: 4;
  }}
  .status-bar.ipad-sb {{ height: 30px; padding: 6px 22px 0; font-size: 12.5px; }}
  .status-bar.dark-ink {{ color: #1B1D24; }}
  .dynamic-island {{
    width: 112px;
    height: 29px;
    border-radius: 20px;
    background: #0D0E12;
    position: absolute;
    left: 50%;
    top: 10px;
    transform: translateX(-50%);
  }}
  .sb-right {{ display: flex; align-items: center; gap: 7px; }}
  .sb-bars {{ display: inline-flex; align-items: flex-end; gap: 2px; height: 11px; }}
  .sb-bars i {{ display: block; width: 3px; background: currentColor; border-radius: 1px; }}
  .sb-bars i:nth-child(1) {{ height: 4px; }}
  .sb-bars i:nth-child(2) {{ height: 6.5px; }}
  .sb-bars i:nth-child(3) {{ height: 9px; }}
  .sb-bars i:nth-child(4) {{ height: 11px; }}
  .sb-battery {{
    width: 24px; height: 12px; border: 1.5px solid currentColor; border-radius: 3.5px;
    padding: 1.5px; display: inline-flex; align-items: center;
  }}
  .sb-battery span {{ display: block; width: 100%; height: 100%; background: currentColor; border-radius: 1.5px; }}

  .ios-tabbar {{
    position: absolute;
    left: 20px; right: 20px; bottom: 16px;
    height: 62px;
    border-radius: 31px;
    background: rgba(255, 255, 255, 0.88);
    backdrop-filter: blur(22px);
    box-shadow: 0 10px 28px rgba(18, 28, 48, 0.10), inset 0 0 0 1px rgba(255,255,255,0.85);
    display: flex;
    align-items: center;
    justify-content: space-around;
    padding: 0 28px;
    z-index: 6;
  }}
  .tab-item {{
    display: flex; flex-direction: column; align-items: center; gap: 3px;
    color: #7D8596; font-size: 11.5px; font-weight: 600;
  }}
  .tab-item svg {{ width: 21px; height: 21px; }}
  .tab-item.active {{ color: #386EF2; }}

  /* ---------------- Split Sidebar (iPad & Mac) ---------------- */
  .split-screen {{ display: flex; flex-direction: column; }}
  .split-body {{ flex: 1; display: flex; min-height: 0; }}
  .app-sidebar {{
    width: 196px;
    background: #EEF2F8;
    border-right: 1px solid rgba(20, 28, 46, 0.07);
    padding: 18px 14px;
    display: flex;
    flex-direction: column;
    gap: 5px;
    flex-shrink: 0;
  }}
  .mac-sb {{ width: 214px; background: rgba(240, 243, 249, 0.96); }}
  .sb-brand {{
    display: flex; align-items: center; gap: 8px;
    font-size: 15px; font-weight: 720; color: #16181F;
    padding: 4px 10px 14px;
  }}
  .sb-brand-dot {{
    width: 10px; height: 10px; border-radius: 50%;
    background: linear-gradient(135deg, #386EF2, #299E94);
  }}
  .sb-section-lbl {{
    font-size: 11px; font-weight: 700; letter-spacing: 0.06em;
    color: #7D8596; text-transform: uppercase;
    padding: 10px 10px 4px;
  }}
  .sb-nav-item {{
    display: flex; align-items: center; gap: 10px;
    padding: 9px 11px; border-radius: 10px;
    font-size: 13.5px; font-weight: 580; color: #3A4050;
  }}
  .sb-nav-item svg {{ width: 17px; height: 17px; flex-shrink: 0; }}
  .sb-nav-item.active {{
    background: rgba(56, 110, 242, 0.12);
    color: #265CE0;
    font-weight: 680;
  }}
  .sb-nav-item.subtle {{ color: #596275; font-size: 13px; }}
  .sb-footer-pill {{
    margin-top: auto;
    display: flex; align-items: center; gap: 7px;
    padding: 9px 12px; border-radius: 12px;
    background: rgba(41, 158, 148, 0.12);
    color: #1B7A71; font-size: 12px; font-weight: 620;
  }}
  .green-dot {{
    width: 7px; height: 7px; border-radius: 50%; background: #22B07D; display: inline-block; flex-shrink: 0;
  }}

  /* ---------------- Slide 01: Sepia Hands-Free Reader ---------------- */
  .reader-sepia-screen {{
    background: #F4ECD8;
    color: #433422;
  }}
  .reader-morning-screen {{
    background: #FAF8F4;
    color: #1F2329;
  }}
  .watch-turned-pill {{
    align-self: center;
    margin-top: 16px;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 7px 16px;
    border-radius: 999px;
    background: rgba(41, 158, 148, 0.14);
    border: 1px solid rgba(41, 158, 148, 0.28);
    color: #1E756D;
    font-size: 12.5px;
    font-weight: 660;
  }}
  .wt-ico svg {{ width: 14px; height: 14px; display: block; }}

  .reader-page {{
    padding: 26px 34px 40px;
    font-family: "New York", "Songti SC", "STSong", "Iowan Old Style", Georgia, serif;
    flex: 1;
  }}
  .reader-page.wide-page {{
    padding: 36px 86px 40px;
    max-width: 780px;
    margin: 0 auto;
  }}
  .family-mac .reader-page.wide-page {{
    padding: 28px 110px 24px;
    max-width: 960px;
  }}
  .reader-running-head {{
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
    font-size: 12px;
    letter-spacing: 0.08em;
    opacity: 0.52;
    margin-bottom: 18px;
    text-align: center;
  }}
  .reader-chapter-title {{
    font-size: 24px;
    font-weight: 700;
    margin-bottom: 20px;
    letter-spacing: 0.01em;
  }}
  .family-ipad .reader-chapter-title {{ font-size: 28px; margin-bottom: 24px; }}
  .family-mac .reader-chapter-title {{ font-size: 26px; margin-bottom: 16px; }}
  .reader-page p {{
    font-size: 18.5px;
    line-height: 1.82;
    margin-bottom: 18px;
    text-align: justify;
  }}
  .family-ipad .reader-page p {{ font-size: 20.5px; line-height: 1.88; margin-bottom: 22px; }}
  .family-mac .reader-page p {{ font-size: 19px; line-height: 1.78; margin-bottom: 15px; }}
  .text-highlight {{
    background: rgba(41, 158, 148, 0.22);
    border-bottom: 2px solid rgba(41, 158, 148, 0.55);
    padding: 1px 2px;
    border-radius: 3px;
  }}

  .handsfree-unlock-pill {{
    position: absolute;
    left: 24px;
    bottom: 26px;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 9px 15px;
    border-radius: 999px;
    background: rgba(67, 52, 34, 0.10);
    border: 1px solid rgba(67, 52, 34, 0.18);
    color: #4D3D2A;
    font-size: 12.5px;
    font-weight: 640;
    backdrop-filter: blur(8px);
  }}
  .hf-lock svg {{ width: 13px; height: 13px; display: block; }}
  .hairline-progress {{
    position: absolute; left: 0; right: 0; bottom: 0; height: 3.5px;
    background: rgba(67, 52, 34, 0.10);
  }}
  .hairline-fill {{
    height: 100%;
    background: linear-gradient(90deg, #386EF2, #299E94);
    border-radius: 0 3px 3px 0;
  }}

  /* ---------------- Floating Apple Watch ---------------- */
  .watch-float {{
    position: absolute;
    right: 44px;
    bottom: 66px;
    z-index: 10;
    display: flex;
    flex-direction: column;
    align-items: center;
  }}
  .watch-float.compact {{
    right: 22px;
    bottom: 72px;
  }}
  .family-mac .watch-float {{
    right: 54px;
    bottom: 34px;
  }}
  .watch-pulse-ring {{
    position: absolute;
    width: 244px; height: 274px;
    border-radius: 68px;
    border: 1.5px solid rgba(41, 158, 148, 0.42);
    top: -12px;
    box-shadow: 0 0 42px rgba(41, 158, 148, 0.25);
  }}
  .watch-float.compact .watch-pulse-ring {{
    width: 196px; height: 224px; border-radius: 54px; top: -10px;
  }}
  .watch-bezel {{
    position: relative;
    width: 218px;
    height: 252px;
    border-radius: 56px;
    padding: 13px;
    background: linear-gradient(145deg, #626774 0%, #23262E 42%, #444854 100%);
    box-shadow:
      0 32px 64px rgba(4, 8, 18, 0.62),
      inset 0 0 0 1.5px rgba(255, 255, 255, 0.34),
      inset 0 0 0 4px rgba(0, 0, 0, 0.55);
  }}
  .watch-float.compact .watch-bezel {{
    width: 174px; height: 204px; border-radius: 44px; padding: 10px;
  }}
  .watch-crown {{
    position: absolute;
    right: -8px; top: 54px;
    width: 11px; height: 42px;
    border-radius: 5px;
    background: linear-gradient(180deg, #9DA3B2, #4C515E, #898F9E);
    box-shadow: 2px 4px 10px rgba(0,0,0,0.45);
  }}
  .watch-float.compact .watch-crown {{ top: 44px; height: 34px; width: 9px; right: -7px; }}
  .watch-side-btn {{
    position: absolute;
    right: -6px; top: 112px;
    width: 7px; height: 52px;
    border-radius: 4px;
    background: linear-gradient(180deg, #747A88, #363A44);
  }}
  .watch-float.compact .watch-side-btn {{ top: 90px; height: 42px; width: 6px; right: -5px; }}
  .watch-glass {{
    width: 100%; height: 100%;
    border-radius: 43px;
    overflow: hidden;
    background: #000;
  }}
  .watch-float.compact .watch-glass {{ border-radius: 34px; }}
  .watch-glass img {{ width: 100%; height: 100%; object-fit: cover; display: block; }}
  .watch-caption-pill {{
    margin-top: 12px;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 7px 14px;
    border-radius: 999px;
    background: rgba(16, 20, 32, 0.82);
    border: 1px solid rgba(255, 255, 255, 0.18);
    color: #F4F6FA;
    font-size: 12px;
    font-weight: 600;
    backdrop-filter: blur(14px);
    box-shadow: 0 12px 26px rgba(0,0,0,0.34);
    white-space: nowrap;
  }}

  /* ---------------- Slide 02: Desk & Bookshelf ---------------- */
  .desk-main, .journal-main {{
    flex: 1;
    padding: 18px 22px 92px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    min-width: 0;
  }}
  .family-ipad .desk-main, .family-ipad .journal-main {{
    padding: 22px 26px 26px;
    gap: 18px;
  }}
  .family-mac .desk-main, .family-mac .journal-main {{
    padding: 18px 26px 22px;
    gap: 15px;
  }}
  .desk-top-row {{
    display: flex; justify-content: space-between; align-items: flex-start;
  }}
  .desk-page-title {{
    font-size: 30px; font-weight: 760; letter-spacing: -0.025em; color: #16181F; line-height: 1.1;
  }}
  .family-mac .desk-page-title {{ font-size: 25px; }}
  .desk-progress-sub {{
    font-size: 13px; color: #677082; margin-top: 4px; font-weight: 500;
  }}
  .desk-top-actions {{ display: flex; align-items: center; gap: 8px; }}
  .watch-status-pill {{
    display: inline-flex; align-items: center; gap: 6px;
    padding: 6px 11px; border-radius: 999px;
    background: #FFFFFF;
    box-shadow: 0 2px 10px rgba(20, 28, 46, 0.06);
    font-size: 12px; font-weight: 640; color: #1E2430;
  }}
  .icon-circle {{
    width: 32px; height: 32px; border-radius: 50%;
    background: #FFFFFF;
    box-shadow: 0 2px 10px rgba(20, 28, 46, 0.06);
    display: inline-flex; align-items: center; justify-content: center;
    color: #2B3240;
  }}
  .icon-circle svg {{ width: 16px; height: 16px; }}

  .hero-reading-card {{
    background: #FFFFFF;
    border-radius: 20px;
    padding: 16px;
    display: flex;
    gap: 16px;
    align-items: center;
    box-shadow: 0 10px 28px rgba(22, 34, 62, 0.07), inset 0 0 0 1px rgba(22, 34, 62, 0.04);
  }}
  .hero-cover-wrap {{
    position: relative;
    width: 96px;
    aspect-ratio: 2 / 3;
    border-radius: 9px;
    overflow: hidden;
    flex-shrink: 0;
    box-shadow: 0 10px 22px rgba(28, 22, 14, 0.24);
  }}
  .family-ipad .hero-cover-wrap {{ width: 112px; }}
  .family-mac .hero-cover-wrap {{ width: 92px; }}
  .hero-cover-wrap img, .cover-wrap img {{
    width: 100%; height: 100%; object-fit: cover; display: block;
  }}
  .spine-crease {{
    position: absolute; left: 0; top: 0; bottom: 0; width: 9px;
    background: linear-gradient(90deg, rgba(0,0,0,0.22) 0%, rgba(255,255,255,0.22) 45%, rgba(0,0,0,0.06) 100%);
  }}
  .hero-info {{ flex: 1; min-width: 0; }}
  .hero-kicker {{
    font-size: 10.5px; font-weight: 740; letter-spacing: 0.08em;
    color: #299E94; text-transform: uppercase;
  }}
  .hero-book-title {{
    font-size: 19px; font-weight: 740; color: #16181F; margin-top: 3px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }}
  .hero-book-meta {{
    font-size: 12.5px; color: #6B7280; margin-top: 3px;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }}
  .hero-prog-row {{
    display: flex; align-items: center; gap: 8px; margin: 11px 0 13px;
  }}
  .hero-prog-track {{
    flex: 1; height: 5px; border-radius: 3px; background: rgba(22, 24, 31, 0.07); overflow: hidden;
  }}
  .hero-prog-fill {{
    height: 100%; border-radius: 3px;
    background: linear-gradient(90deg, #386EF2, #299E94);
  }}
  .hero-prog-pct {{ font-size: 11.5px; font-weight: 700; color: #386EF2; }}
  .hero-cta-row {{ display: flex; gap: 8px; flex-wrap: nowrap; }}
  .cta-primary {{
    display: inline-flex; align-items: center; gap: 6px;
    padding: 9px 14px; border-radius: 12px;
    background: linear-gradient(135deg, #386EF2, #299E94);
    color: #FFFFFF; font-size: 12.5px; font-weight: 660;
    box-shadow: 0 6px 16px rgba(56, 110, 242, 0.28);
    white-space: nowrap;
  }}
  .cta-primary svg {{ width: 11px; height: 11px; }}
  .cta-secondary {{
    display: inline-flex; align-items: center; gap: 5px;
    padding: 9px 12px; border-radius: 12px;
    background: rgba(56, 110, 242, 0.09);
    color: #2B5DE0; font-size: 12.5px; font-weight: 640;
    white-space: nowrap;
  }}
  .cta-secondary svg {{ width: 13px; height: 13px; }}

  .shelf-header-row {{
    display: flex; justify-content: space-between; align-items: center; gap: 10px; flex-wrap: wrap;
  }}
  .shelf-title {{ font-size: 17px; font-weight: 730; color: #16181F; }}
  .filter-row {{ display: flex; gap: 6px; }}
  .filter-chip {{
    padding: 5px 10px; border-radius: 999px;
    font-size: 11.5px; font-weight: 600;
    background: rgba(22, 24, 31, 0.055); color: #5D6575;
  }}
  .filter-chip.active {{
    background: #1B202C; color: #FFFFFF;
  }}
  .shelf-grid {{
    display: grid; gap: 14px;
  }}
  .shelf-grid.cols-3 {{ grid-template-columns: repeat(3, 1fr); }}
  .family-ipad .shelf-grid.cols-3 {{ gap: 20px; }}
  .shelf-grid.cols-4 {{ grid-template-columns: repeat(4, 1fr); gap: 18px; }}
  .shelf-grid.cols-5 {{ grid-template-columns: repeat(5, 1fr); gap: 16px; }}
  .shelf-card {{ display: flex; flex-direction: column; min-width: 0; }}
  .cover-wrap {{
    position: relative;
    width: 100%;
    aspect-ratio: 2 / 3;
    border-radius: 10px;
    overflow: hidden;
    box-shadow: 0 10px 22px rgba(24, 30, 46, 0.16);
  }}
  .cover-wrap.import-tile {{
    background: rgba(56, 110, 242, 0.05);
    border: 1.5px dashed rgba(56, 110, 242, 0.28);
    box-shadow: none;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 12px;
    text-align: center;
    color: #2E62E2;
  }}
  .import-plus {{
    width: 34px; height: 34px; border-radius: 50%;
    background: rgba(56, 110, 242, 0.12);
    display: flex; align-items: center; justify-content: center;
  }}
  .import-plus svg {{ width: 17px; height: 17px; }}
  .import-lbl {{ font-size: 11.5px; font-weight: 650; line-height: 1.25; }}
  .cover-badge {{
    position: absolute; right: 7px; bottom: 7px;
    padding: 3px 7px; border-radius: 6px;
    background: rgba(16, 19, 28, 0.72);
    color: #FFFFFF; font-size: 10.5px; font-weight: 680;
    backdrop-filter: blur(8px);
  }}
  .book-title {{
    margin-top: 8px; font-size: 13px; font-weight: 660; color: #16181F;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }}
  .book-author {{
    margin-top: 2px; font-size: 11.5px; color: #747D8E;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }}

  /* ---------------- Slide 03: Paper Presets & Reader Dock ---------------- */
  .reader-top-chrome {{
    display: flex; justify-content: space-between; align-items: center;
    padding: 8px 22px 10px;
    font-size: 13px; color: #676C77;
    border-bottom: 1px solid rgba(25, 28, 36, 0.06);
  }}
  .reader-top-chrome.hide {{ display: none; }}
  .rtc-back {{ color: #386EF2; font-weight: 600; }}
  .rtc-title {{ font-weight: 620; color: #2B2F38; }}
  .rtc-mark svg {{ width: 16px; height: 16px; }}

  .reader-floating-dock {{
    position: absolute;
    left: 16px; right: 16px; bottom: 18px;
    background: rgba(255, 255, 255, 0.92);
    backdrop-filter: blur(22px);
    border-radius: 24px;
    padding: 14px 16px 13px;
    box-shadow: 0 16px 38px rgba(16, 22, 36, 0.16), inset 0 0 0 1px rgba(255,255,255,0.9);
  }}
  .dock-top-meta {{
    display: flex; justify-content: space-between; align-items: center; gap: 10px; margin-bottom: 12px;
  }}
  .dock-presets-row {{ display: flex; gap: 6px; }}
  .preset-chip {{
    display: inline-flex; align-items: center; gap: 5px;
    padding: 5px 9px 5px 6px; border-radius: 999px;
    background: rgba(22, 24, 31, 0.05);
    font-size: 11.5px; font-weight: 620; color: #363C49;
  }}
  .preset-chip.active {{
    background: rgba(56, 110, 242, 0.12);
    box-shadow: inset 0 0 0 1.5px #386EF2;
    color: #265CE0;
  }}
  .swatch {{
    width: 20px; height: 20px; border-radius: 50%;
    display: inline-flex; align-items: center; justify-content: center;
    font-size: 9.5px; font-weight: 700;
    box-shadow: inset 0 0 0 1px rgba(0,0,0,0.12);
  }}
  .dock-rem-time {{
    font-size: 11.5px; font-weight: 600; color: #6B7280; white-space: nowrap;
  }}
  .dock-slider {{
    position: relative; height: 4px; border-radius: 2px;
    background: rgba(22, 24, 31, 0.10); margin-bottom: 13px;
  }}
  .dock-slider-fill {{
    height: 100%; border-radius: 2px;
    background: linear-gradient(90deg, #386EF2, #299E94);
  }}
  .dock-slider-knob {{
    position: absolute; top: 50%; transform: translate(-50%, -50%);
    width: 14px; height: 14px; border-radius: 50%;
    background: #FFFFFF; box-shadow: 0 2px 7px rgba(0,0,0,0.25), inset 0 0 0 2px #299E94;
  }}
  .dock-actions-row {{
    display: flex; justify-content: space-between; align-items: center;
  }}
  .dock-btn {{
    display: flex; flex-direction: column; align-items: center; gap: 3px;
    font-size: 10.5px; font-weight: 580; color: #4C5364;
  }}
  .dock-btn svg {{ width: 18px; height: 18px; }}
  .dock-btn .aa-glyph {{ font-size: 15px; font-weight: 720; line-height: 18px; }}
  .dock-btn.active-teal {{ color: #1E857C; font-weight: 680; }}

  .floating-presets-strip {{
    position: absolute;
    bottom: 24px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 9;
    display: flex;
    gap: 10px;
    padding: 10px 14px;
    border-radius: 999px;
    background: rgba(16, 20, 34, 0.78);
    border: 1px solid rgba(255, 255, 255, 0.22);
    backdrop-filter: blur(20px);
    box-shadow: 0 20px 44px rgba(4, 8, 20, 0.45);
  }}
  .fp-chip {{
    display: inline-flex; align-items: center; gap: 7px;
    padding: 6px 12px 6px 7px; border-radius: 999px;
    color: rgba(255,255,255,0.88); font-size: 13px; font-weight: 620;
  }}
  .fp-chip.active {{
    background: rgba(255, 255, 255, 0.16);
    box-shadow: inset 0 0 0 1.5px rgba(41, 158, 148, 0.9);
  }}
  .fp-dot {{
    width: 26px; height: 26px; border-radius: 50%;
    display: inline-flex; align-items: center; justify-content: center;
    font-size: 11px; font-weight: 720;
    box-shadow: 0 2px 6px rgba(0,0,0,0.28);
  }}

  /* Mac Reader Toolbar */
  .mac-reader-toolbar {{
    display: flex; justify-content: space-between; align-items: center;
    padding: 10px 20px;
    background: rgba(250, 248, 244, 0.94);
    border-bottom: 1px solid rgba(25, 28, 36, 0.08);
  }}
  .mrt-left, .mrt-right {{ display: flex; align-items: center; gap: 10px; }}
  .mrt-title {{ font-size: 14px; font-weight: 660; color: #222630; }}
  .mrt-presets {{ display: flex; gap: 6px; }}
  .mrt-chip {{
    display: inline-flex; align-items: center; gap: 6px;
    padding: 6px 11px; border-radius: 9px;
    background: rgba(22, 24, 31, 0.06); color: #2E3442;
    font-size: 12px; font-weight: 620;
  }}
  .mrt-chip svg {{ width: 14px; height: 14px; }}
  .mrt-chip.teal {{
    background: rgba(41, 158, 148, 0.15); color: #197A71;
  }}
  .mrt-chip kbd {{
    font-family: -apple-system, sans-serif; font-size: 10.5px; opacity: 0.72;
    padding: 1px 4px; border-radius: 4px; background: rgba(255,255,255,0.65);
  }}
  .mac-reader-footer {{
    margin-top: auto;
    display: flex; justify-content: space-between; align-items: center;
    padding: 10px 26px;
    font-size: 12px; color: #727988;
    border-top: 1px solid rgba(25, 28, 36, 0.06);
  }}

  /* ---------------- Slide 04: Journal & Floating Postcard ---------------- */
  .kpi-duo {{ display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }}
  .kpi-card {{
    background: #FFFFFF; border-radius: 18px; padding: 15px 16px;
    box-shadow: 0 8px 22px rgba(22, 34, 62, 0.06), inset 0 0 0 1px rgba(22,34,62,0.04);
  }}
  .kpi-top {{ display: flex; justify-content: space-between; align-items: center; }}
  .kpi-val {{ font-size: 24px; font-weight: 760; color: #16181F; }}
  .kpi-val.teal-val {{ color: #208C82; }}
  .kpi-ring {{
    width: 36px; height: 36px; border-radius: 50%;
    background: conic-gradient(#386EF2 0% 45%, #299E94 45% 80%, #E8EDF5 80% 100%);
    display: flex; align-items: center; justify-content: center;
  }}
  .kpi-ring span {{
    width: 28px; height: 28px; border-radius: 50%; background: #FFF;
    display: flex; align-items: center; justify-content: center;
    font-size: 9.5px; font-weight: 720; color: #265CE0;
  }}
  .streak-flame {{
    width: 34px; height: 34px; border-radius: 50%;
    background: rgba(41, 158, 148, 0.14); color: #208C82;
    display: flex; align-items: center; justify-content: center; font-size: 16px;
  }}
  .kpi-lbl {{ font-size: 12px; color: #6B7280; margin-top: 8px; font-weight: 500; }}

  .heatmap-card {{
    background: #FFFFFF; border-radius: 18px; padding: 15px 16px;
    box-shadow: 0 8px 22px rgba(22, 34, 62, 0.06), inset 0 0 0 1px rgba(22,34,62,0.04);
  }}
  .hm-head {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }}
  .hm-title {{ font-size: 14.5px; font-weight: 700; color: #16181F; }}
  .hm-link {{ font-size: 12px; font-weight: 620; color: #386EF2; }}
  .hm-grid {{
    display: grid; grid-template-columns: repeat(7, 1fr); gap: 7px;
  }}
  .hm-cell {{
    height: 22px; border-radius: 6px; display: block;
  }}
  .family-mac .hm-cell {{ height: 19px; }}
  .lv-0 {{ background: #EEF2F7; }}
  .lv-1 {{ background: #CBEAE6; }}
  .lv-2 {{ background: #89D4CB; }}
  .lv-3 {{ background: #46B5AA; }}
  .lv-4 {{ background: #228E84; }}
  .hm-legend {{
    display: flex; align-items: center; justify-content: flex-end; gap: 5px;
    margin-top: 10px; font-size: 11px; color: #7C8494;
  }}
  .hm-legend .hm-cell {{ width: 12px; height: 12px; border-radius: 3px; }}

  .quote-section-head {{
    display: flex; justify-content: space-between; align-items: baseline;
  }}
  .quote-hint {{ font-size: 11.5px; color: #7A8292; }}
  .quote-list {{ display: flex; flex-direction: column; gap: 10px; }}
  .quote-row-card {{
    background: #FFFFFF; border-radius: 16px; padding: 13px 14px;
    display: flex; gap: 11px;
    box-shadow: 0 6px 18px rgba(22, 34, 62, 0.05), inset 0 0 0 1px rgba(22,34,62,0.04);
  }}
  .quote-accent-bar {{ width: 3.5px; border-radius: 4px; flex-shrink: 0; }}
  .quote-row-body {{ flex: 1; min-width: 0; }}
  .quote-row-text {{
    font-family: "New York", "Songti SC", Georgia, serif;
    font-size: 13.5px; line-height: 1.55; color: #242834;
  }}
  .quote-row-foot {{
    margin-top: 8px; display: flex; justify-content: space-between; align-items: center;
    font-size: 11.5px; color: #778091;
  }}
  .postcard-mini-btn {{
    display: inline-flex; align-items: center; gap: 4px;
    padding: 4px 9px; border-radius: 999px;
    background: rgba(56, 110, 242, 0.09); color: #2E62E2; font-weight: 640; font-size: 11px;
  }}
  .postcard-mini-btn svg {{ width: 11px; height: 11px; }}

  /* Floating Single-Quote Postcard */
  .postcard-float {{
    position: absolute;
    right: 46px;
    bottom: 44px;
    width: 396px;
    z-index: 10;
    background: linear-gradient(155deg, #FBF6EA 0%, #F3E9D4 100%);
    color: #3A2E1F;
    border-radius: 22px;
    padding: 26px 28px 24px;
    transform: rotate(-2.2deg);
    box-shadow:
      0 34px 72px rgba(40, 28, 12, 0.28),
      0 8px 22px rgba(40, 28, 12, 0.14),
      inset 0 0 0 1px rgba(154, 124, 78, 0.24);
  }}
  .postcard-float.compact {{
    width: 332px;
    right: 26px;
    bottom: 48px;
    padding: 20px 22px 18px;
  }}
  .family-mac .postcard-float {{
    right: 52px;
    bottom: 34px;
    width: 400px;
  }}
  .pc-kicker {{
    font-size: 10.5px; font-weight: 740; letter-spacing: 0.16em;
    color: #8C7352;
  }}
  .pc-mark {{
    font-family: Georgia, serif; font-size: 46px; line-height: 0.78;
    color: rgba(41, 158, 148, 0.42); margin-top: 10px;
  }}
  .pc-quote {{
    font-family: "New York", "Songti SC", "STSong", Georgia, serif;
    font-size: 18px; line-height: 1.65; font-weight: 560; color: #2E2417;
    margin-top: 4px;
  }}
  .postcard-float.compact .pc-quote {{ font-size: 15.5px; line-height: 1.6; }}
  .pc-divider {{
    height: 1px; background: rgba(138, 112, 74, 0.22); margin: 16px 0 12px;
  }}
  .pc-footer {{
    display: flex; justify-content: space-between; align-items: center;
  }}
  .pc-book {{ font-size: 13px; font-weight: 720; color: #362A1C; }}
  .pc-author {{ font-size: 11.5px; color: #846E51; margin-top: 2px; }}
  .pc-dots {{ display: flex; gap: 7px; }}
  .pc-dot {{
    width: 18px; height: 18px; border-radius: 50%;
    box-shadow: inset 0 0 0 1px rgba(0,0,0,0.18);
  }}
  .pc-dot.active {{ box-shadow: 0 0 0 2px #FBF6EA, 0 0 0 3.5px #299E94; }}

  /* ---------------- Slide 05: Settings & Ecosystem ---------------- */
  .settings-main {{
    flex: 1; padding: 18px 22px 26px; display: flex; flex-direction: column; gap: 14px;
  }}
  .app-badge-row {{ display: flex; align-items: center; gap: 13px; }}
  .mini-app-icon {{
    width: 48px; height: 48px; border-radius: 12px;
    box-shadow: 0 6px 16px rgba(24, 46, 110, 0.24);
  }}
  .settings-title {{ font-size: 26px; font-weight: 760; color: #16181F; line-height: 1.1; }}
  .settings-sub {{ font-size: 12.5px; color: #6E7788; margin-top: 3px; }}
  .set-section-lbl {{
    font-size: 11px; font-weight: 720; letter-spacing: 0.08em;
    color: #6B7486; text-transform: uppercase; padding-left: 6px;
  }}
  .set-card {{
    background: #FFFFFF; border-radius: 18px;
    box-shadow: 0 8px 24px rgba(22, 34, 62, 0.06), inset 0 0 0 1px rgba(22,34,62,0.04);
  }}
  .highlight-toggle-card {{
    padding: 15px 16px;
    background: linear-gradient(135deg, rgba(56,110,242,0.08), rgba(41,158,148,0.08)), #FFFFFF;
    box-shadow: 0 10px 26px rgba(56,110,242,0.10), inset 0 0 0 1.5px rgba(56,110,242,0.22);
  }}
  .toggle-row {{ display: flex; align-items: center; justify-content: space-between; gap: 14px; }}
  .toggle-title {{ font-size: 15.5px; font-weight: 700; color: #16181F; }}
  .toggle-sub {{ font-size: 12px; color: #5F687A; margin-top: 3px; }}
  .ios-switch {{
    width: 48px; height: 28px; border-radius: 999px; background: #299E94;
    padding: 3px; display: flex; justify-content: flex-end; flex-shrink: 0;
    box-shadow: inset 0 1px 2px rgba(0,0,0,0.12);
  }}
  .ios-switch span {{
    width: 22px; height: 22px; border-radius: 50%; background: #FFF;
    box-shadow: 0 2px 5px rgba(0,0,0,0.2);
  }}
  .list-card {{ padding: 4px 16px; }}
  .set-row {{
    display: flex; align-items: center; gap: 12px;
    padding: 13px 0;
    border-bottom: 1px solid rgba(22, 24, 31, 0.06);
  }}
  .set-row:last-child {{ border-bottom: none; }}
  .set-ico {{
    width: 30px; height: 30px; border-radius: 8px;
    color: #FFF; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0;
  }}
  .set-ico svg {{ width: 16px; height: 16px; }}
  .set-name {{ font-size: 14.5px; font-weight: 580; color: #1B1E28; flex: 1; }}
  .row-val {{ font-size: 13px; color: #6E7688; font-weight: 500; }}
  .row-val-green {{ font-size: 13px; color: #1E8A7E; font-weight: 650; }}
  .set-chev {{ font-size: 16px; color: #B4BCC9; }}

  .formats-card {{
    background: #FFFFFF; border-radius: 18px; padding: 14px 16px;
    box-shadow: 0 8px 22px rgba(22, 34, 62, 0.05), inset 0 0 0 1px rgba(22,34,62,0.04);
  }}
  .fmt-head {{
    font-size: 11px; font-weight: 720; letter-spacing: 0.08em; color: #6B7486; margin-bottom: 10px;
  }}
  .fmt-row {{ display: flex; flex-wrap: wrap; gap: 7px; }}
  .fmt-pill {{
    padding: 6px 11px; border-radius: 8px;
    background: #F0F4FA; color: #26488A; font-size: 12px; font-weight: 700;
  }}
  .sync-status-card {{
    background: linear-gradient(135deg, rgba(41,158,148,0.08), rgba(56,110,242,0.08)), #FFFFFF;
    border-radius: 18px; padding: 14px 16px;
    box-shadow: 0 8px 22px rgba(22, 34, 62, 0.05), inset 0 0 0 1px rgba(41,158,148,0.18);
  }}
  .sync-card-top {{
    display: flex; align-items: center; gap: 8px; margin-bottom: 11px;
  }}
  .sync-card-title {{ font-size: 13px; font-weight: 700; color: #176E66; }}
  .sync-devices-row {{
    display: grid; grid-template-columns: repeat(4, 1fr); gap: 7px;
  }}
  .sync-dev-chip {{
    display: flex; align-items: center; justify-content: center; gap: 4px;
    padding: 7px 6px; border-radius: 10px;
    background: #FFFFFF;
    box-shadow: 0 2px 8px rgba(22,34,62,0.06);
    font-size: 11.5px; font-weight: 660; color: #1E283B;
  }}
  .sync-dev-chip i {{ font-style: normal; color: #22B07D; font-weight: 800; }}
  .ci-frame .sync-status-card {{ display: none; }}
  .eco-device-pill {{
    position: absolute;
    bottom: 24px;
    left: 50%; transform: translateX(-50%);
    z-index: 10;
    display: inline-flex; align-items: center; gap: 10px;
    padding: 10px 22px; border-radius: 999px;
    background: rgba(255, 255, 255, 0.86);
    border: 1px solid rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(18px);
    box-shadow: 0 14px 36px rgba(18, 42, 68, 0.16);
    color: #16243A; font-size: 14px; font-weight: 700;
    white-space: nowrap;
  }}
  .eco-device-pill i {{ font-style: normal; color: #299E94; }}

  /* ---------------- Mac Desktop Stage & Window Chrome ---------------- */
  .mac-stage {{
    position: relative;
    z-index: 4;
    flex: 1;
    width: 100%;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding: 12px 72px 36px;
  }}
  .mac-window {{
    border-radius: 16px;
    overflow: hidden;
    background: #F6F8FC;
    display: flex;
    flex-direction: column;
    box-shadow:
      0 38px 90px rgba(8, 14, 28, 0.42),
      0 10px 28px rgba(8, 14, 28, 0.22),
      0 0 0 1px rgba(255, 255, 255, 0.34);
  }}
  .mac-win-hero {{
    width: 1180px;
    height: 648px;
  }}
  .mac-titlebar {{
    height: 36px;
    background: #EDEFF4;
    border-bottom: 1px solid rgba(20, 24, 34, 0.08);
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 14px;
    flex-shrink: 0;
  }}
  .mac-lights {{ display: flex; gap: 8px; width: 64px; }}
  .mac-lights span {{ width: 12px; height: 12px; border-radius: 50%; display: block; }}
  .ml-r {{ background: #FF5F57; }}
  .ml-y {{ background: #FEBC2E; }}
  .ml-g {{ background: #28C840; }}
  .mac-tb-title {{ font-size: 12.5px; font-weight: 620; color: #4A5160; }}
  .mac-tb-spacer {{ width: 64px; }}
  .mac-window-body {{ flex: 1; min-height: 0; display: flex; flex-direction: column; }}

  /* Slide 05 Mac Multi-Window + Companion iPhone */
  .stage-ecosystem {{
    padding: 10px 44px 30px;
  }}
  .mac-win-back {{
    position: absolute;
    left: 56px;
    top: 8px;
    width: 780px;
    height: 604px;
    z-index: 2;
  }}
  .mac-win-front {{
    position: absolute;
    right: 344px;
    top: 72px;
    width: 530px;
    height: 558px;
    z-index: 4;
  }}
  .mac-win-front .reader-page.wide-page {{
    padding: 20px 36px 24px;
  }}
  .mac-win-front .reader-page p {{
    font-size: 15px;
    line-height: 1.72;
    margin-bottom: 12px;
  }}
  .companion-iphone {{
    position: absolute;
    right: 48px;
    top: 96px;
    width: 274px;
    height: 554px;
    z-index: 6;
    border-radius: 38px;
    padding: 8px;
    background: linear-gradient(145deg, #3A3D45, #1A1C21);
    box-shadow:
      0 30px 70px rgba(8, 16, 34, 0.44),
      inset 0 0 0 1.5px rgba(255, 255, 255, 0.25);
  }}
  .ci-frame {{
    width: 100%; height: 100%; border-radius: 30px; overflow: hidden;
    background: #F6F8FC;
  }}
  .ci-frame .status-bar {{ height: 30px; padding: 6px 14px 0; font-size: 10px; }}
  .ci-frame .dynamic-island {{ width: 64px; height: 17px; top: 6px; }}
  .ci-frame .settings-main {{ padding: 10px 12px; gap: 8px; }}
  .ci-frame .mini-app-icon {{ width: 30px; height: 30px; border-radius: 8px; }}
  .ci-frame .settings-title {{ font-size: 16px; }}
  .ci-frame .settings-sub {{ font-size: 9.5px; }}
  .ci-frame .set-section-lbl {{ font-size: 8.5px; }}
  .ci-frame .highlight-toggle-card {{ padding: 9px 10px; border-radius: 12px; }}
  .ci-frame .toggle-title {{ font-size: 11px; }}
  .ci-frame .toggle-sub {{ font-size: 8.5px; }}
  .ci-frame .ios-switch {{ width: 32px; height: 18px; padding: 2px; }}
  .ci-frame .ios-switch span {{ width: 14px; height: 14px; }}
  .ci-frame .list-card {{ padding: 2px 10px; border-radius: 12px; }}
  .ci-frame .set-row {{ padding: 7px 0; gap: 7px; }}
  .ci-frame .set-ico {{ width: 20px; height: 20px; border-radius: 5px; }}
  .ci-frame .set-ico svg {{ width: 11px; height: 11px; }}
  .ci-frame .set-name {{ font-size: 10px; }}
  .ci-frame .row-val, .ci-frame .row-val-green {{ font-size: 9.5px; }}
  .ci-frame .formats-card {{ padding: 8px 10px; border-radius: 12px; }}
  .ci-frame .fmt-head {{ font-size: 8.5px; margin-bottom: 6px; }}
  .ci-frame .fmt-pill {{ padding: 3px 6px; font-size: 8.5px; }}
  .sync-float-badge {{
    position: absolute;
    left: 88px;
    bottom: 24px;
    z-index: 8;
    display: inline-flex; align-items: center; gap: 8px;
    padding: 9px 18px; border-radius: 999px;
    background: rgba(255, 255, 255, 0.90);
    border: 1px solid rgba(255, 255, 255, 0.96);
    backdrop-filter: blur(18px);
    box-shadow: 0 12px 30px rgba(14, 34, 60, 0.16);
    font-size: 13px; font-weight: 700; color: #1A2A42;
  }}
</style>
</head>
<body>
  <div class="canvas family-{family}">
    <img class="backdrop" src="{bg_uri}" alt="">
    <div class="scrim {mood}"></div>
    <header class="header {header_theme}">
      <div class="badge-pill"><span class="badge-dot"></span><span>{esc(slide_meta['badge'])}</span></div>
      <h1 class="headline">{esc(slide_meta['title'])}</h1>
      <p class="subtitle">{esc(slide_meta['subtitle'])}</p>
    </header>
    {stage}
  </div>
</body>
</html>"""


def render_one(job):
    locale, device_key, slide_key, html_str, out_path, tmp_dir = job
    spec = DEVICES[device_key]
    cw = spec["w"] // 2
    ch = spec["h"] // 2

    html_file = tmp_dir / f"{locale}_{device_key}_{slide_key}.html"
    raw_png = tmp_dir / f"{locale}_{device_key}_{slide_key}.png"
    html_file.write_text(html_str, encoding="utf-8")

    cmd = [
        CHROME_BIN,
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-sandbox",
        "--disable-background-networking",
        "--disable-default-apps",
        "--force-device-scale-factor=2",
        f"--window-size={cw},{ch}",
        f"--screenshot={raw_png}",
        html_file.as_uri(),
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    if res.returncode != 0 or not raw_png.exists():
        raise RuntimeError(f"Chrome failed on {locale}/{device_key}/{slide_key}: {res.stderr.decode()[:300]}")

    # Convert to exact target dimensions, RGB (no alpha), and embed sRGB ICC
    im = Image.open(raw_png)
    if im.size != (spec["w"], spec["h"]):
        im = im.resize((spec["w"], spec["h"]), Image.Resampling.LANCZOS)
    if im.mode != "RGB":
        bg = Image.new("RGB", im.size, (255, 255, 255))
        if im.mode == "RGBA":
            bg.paste(im, mask=im.split()[3])
        else:
            bg.paste(im)
        im = bg

    out_path.parent.mkdir(parents=True, exist_ok=True)
    icc_bytes = SRGB_ICC.read_bytes() if SRGB_ICC.exists() else None
    save_kwargs = {"format": "PNG", "optimize": True}
    if icc_bytes:
        save_kwargs["icc_profile"] = icc_bytes
    im.save(out_path, **save_kwargs)
    return str(out_path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--locales", nargs="*", default=LOCALES)
    parser.add_argument("--devices", nargs="*", default=list(DEVICES.keys()))
    parser.add_argument("--slides", nargs="*", default=SLIDES)
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()

    assets = discover_assets()
    tmp_dir = Path(tempfile.mkdtemp(prefix="pp_store_v2_"))
    try:
        jobs = []
        for loc in args.locales:
            for dev in args.devices:
                for slide in args.slides:
                    html_str = build_slide_html(loc, dev, slide, assets)
                    out_path = OUT_ROOT / loc / dev / f"{slide}.png"
                    jobs.append((loc, dev, slide, html_str, out_path, tmp_dir))

        print(f"Rendering {len(jobs)} App Store screenshots using {args.workers} workers...")
        done = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as ex:
            futs = [ex.submit(render_one, j) for j in jobs]
            for f in concurrent.futures.as_completed(futs):
                path = f.result()
                done += 1
                if done % 10 == 0 or done == len(jobs):
                    print(f"  [{done}/{len(jobs)}] latest: {path}")
        print(f"All {done} screenshots generated under {OUT_ROOT}")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
