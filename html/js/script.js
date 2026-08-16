const CAPACITY_NEAR_FULL_RATIO = 0.85;
let SECONDARY_CAPACITY = 0;

const RARITY_THEME = {
    1: { labelKey: "rarity1", border: "#94a3b8", inset: "rgba(148, 163, 184, 0.35)" },
    2: { labelKey: "rarity2", border: "#4ade80", inset: "rgba(74, 222, 128, 0.35)" },
    3: { labelKey: "rarity3", border: "#60a5fa", inset: "rgba(96, 165, 250, 0.38)" },
    4: { labelKey: "rarity4", border: "#c084fc", inset: "rgba(192, 132, 252, 0.38)" },
    5: { labelKey: "rarity5", border: "#fbbf24", inset: "rgba(251, 191, 36, 0.42)" },
};

const RARITY_FALLBACK_LABELS = {
    1: "Common",
    2: "Uncommon",
    3: "Rare",
    4: "Epic",
    5: "Legendary",
};

const RARITY_SLOT_IMAGE_NAME = {
    1: "common",
    2: "uncommon",
    3: "rare",
    4: "epic",
    5: "legendary",
};

const UTILS = {

    GET_ITEM_METADATA_INFO: function (item, isCustom) {

        this.CACHE_IMAGE(item);

        const tooltipData = item.metadata?.tooltip ? "<br>" + item.metadata.tooltip : "";

        const degradation = isCustom ? this.GET_DEGRADATION_CUSTOM(item) : this.GET_DEGRADATION_MAIN(item);

        const image = item.type !== "item_weapon"
            ? item.metadata?.image ? item.metadata.image : item.name ? item.name : "default" // items
            : item.name ? item.name : "default"; // weapons

        const weight = item.metadata?.weight ?
            item.metadata.weight : item.weight ? item.weight : 0;

        const label = item.type !== "item_weapon"
            ? item.metadata?.label ? item.metadata.label : item.label // items
            : item?.custom_label ? item.custom_label : item.label; // weapons

        const description = item.type !== "item_weapon"
            ? item.metadata?.description ? item.metadata.description : item.desc // items
            : item?.custom_desc ? item.custom_desc : item.desc; // weapons

        let durability = "";
        if (item.type !== "item_weapon") {
            const rawD = item.durability;
            if (rawD != null && rawD !== "") {
                const d = Number(rawD);
                if (Number.isFinite(d)) {
                    const color = this.GET_DEGRADATION_COLOR(Math.min(100, Math.max(0, d)));
                    const lim = LANGUAGE.labels?.durability != null ? LANGUAGE.labels.durability : "Durability ";
                    const shown = Number.isInteger(d) ? String(d) : String(+d.toFixed(2));
                    durability = `<br>${lim}<span style="color: ${color}">${shown}%</span>`;
                }
            }
        }

        return { tooltipData, degradation, image, label, weight, description, durability };
    },


    GET_ITEM_WEIGHT: function (weight, count) {
        return weight != null ? `<br>${LANGUAGE.labels?.weight} ${(weight * count).toFixed(2)} ${Config.WeightMeasure}` : `<br>${LANGUAGE.labels?.weight} ${(count / 4).toFixed(2)} ${Config.WeightMeasure}`;
    },

    GET_GROUP_KEY: function (group) {
        let groupKey;
        if (window.ITEM_GROUPS && Object.keys(window.ITEM_GROUPS).length > 0) {
            groupKey = Object.keys(window.ITEM_GROUPS).find(key =>
                key !== "all" && window.ITEM_GROUPS[key].types.includes(group)
            );
        }
        return groupKey;
    },


    APPLY_INV_CAPACITY_WARNING: function ($el, current, max) {
        if (!$el || !$el.length) {
            return;
        }
        const c = Number(current);
        const m = Number(max);
        if (Number.isFinite(m) && m > 0 && Number.isFinite(c) && c >= 0) {
            $el.toggleClass("inv-weight-near-full", c / m >= CAPACITY_NEAR_FULL_RATIO);
        } else {
            $el.removeClass("inv-weight-near-full");
        }
    },

    PARSE_HUD_AMOUNT: function ($element) {
        const raw = ($element.text() || "").trim().replace(/[^0-9.-]/g, "");
        const n = parseFloat(raw);
        return Number.isFinite(n) ? n : 0;
    },


    PROCESS_EVENT_VALIDATION: function (ms = 1000) {
        isValidating = true;
        const timer = setTimeout(() => {
            isValidating = false;
            clearTimeout(timer);
        }, ms);
    },

    IS_INT: function (n) {
        return n != "" && !isNaN(n) && Math.round(n) == n;
    },

    UPDATE_HINT_VISIBILITY: function () {
        $("#inv-hint-secondary").toggle($("#secondInventoryHud").is(":visible"));
        $("#inv-hint-main-only").toggle(type === "main");
    },

    ESCAPE_HTML: function (text) {
        if (text == null || text === "") return "";
        return String(text)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    },

    CACHE_IMAGE: function (item) {
        if (item.type === "item_weapon") return;
        const image = item.metadata?.image;

        if (image && !(image in imageCache)) {
            this.PRELOAD_IMAGES([image]);
        }

    },

    SAFE_ITEM_IMAGE: function (imageKey) {
        const k = (imageKey || "placeholder").toString();
        return k.replace(/[^a-zA-Z0-9._-]/g, "_") || "placeholder";
    },

    GET_DEGRADATION_COLOR: function (degradation) {
        if (degradation < 15) {
            return "red";
        } else if (degradation < 40) {
            return "orange";
        } else if (degradation < 70) {
            return "gold";
        } else {
            return "green";
        }
    },

    TRIM_TRAILING_EMPTY_SLOTS: function (slots, maxSlots) {
        if (!slots || !Array.isArray(slots)) return slots;
        while (slots.length > maxSlots && slots[slots.length - 1] && slots[slots.length - 1].k === "empty") {
            slots.pop();
        }
        return slots;
    },

    PRELOAD_IMAGES: function (images) {
        if (!images) return;
        $.each(images, function (_, image) {
            const img = new Image();
            img.onload = () => {
                imageCache[image] = `url("img/items/${image}.png");`;
            };
            img.onerror = () => {
                imageCache[image] = `url("img/items/placeholder.png");`;
                // console.log("no image for item", image);

            };
            img.src = `img/items/${image}.png`;
        });
    },

    RESOLVE_ITEM_GROUP_TITLE_TEXT: function (key) {
        const k = (key == null || key === "") ? "all" : String(key);
        if (k === "all") {
            return (LANGUAGE && (LANGUAGE.inventoryall || LANGUAGE.all)) || "All";
        }
        try {
            if (window.ITEM_GROUPS && window.ITEM_GROUPS[k]) {
                const label = window.ITEM_GROUPS[k].label;
                if (label != null && String(label).trim() !== "") {
                    return String(label);
                }
            }
        } catch (e) {
            /* ignore */
        }
        return k
            .replace(/[_-]+/g, " ")
            .replace(/\s+/g, " ")
            .trim()
            .replace(/\b\w/g, (m) => m.toUpperCase()) || k;
    },

    GET_ITEM_DEGRADATION_PERCENTAGE: function (item) {
        if (item.maxDegradation === 0) return 1;
        const now = TIME_NOW;
        const maxDegradeSeconds = item.maxDegradation * 60;
        const elapsedSeconds = now - item.degradation;
        const degradationPercentage = Math.max(0, ((maxDegradeSeconds - elapsedSeconds) / maxDegradeSeconds) * 100);
        return degradationPercentage;
    },

    ITEM_DECAY_FULLY_SPOILED: function (item) {
        if (!item || item.maxDegradation === 0) return false;
        return this.GET_ITEM_DEGRADATION_PERCENTAGE(item) === 0;
    },

    ITEM_DURABILITY_FULLY_SPENT: function (item) {
        if (!item || item.durability == null || item.durability === "") return false;
        const d = Number(item.durability);
        return Number.isFinite(d) && d === 0;
    },

    ITEM_SLOT_OPACITY: function (item) {
        if (!item || item.type === "item_weapon") return "1";
        return this.ITEM_DECAY_FULLY_SPOILED(item) || this.ITEM_DURABILITY_FULLY_SPENT(item) ? "0.5" : "1";
    },

    ITEM_ICON_OPACITY_EXTRA: function (item) {
        const o = this.ITEM_SLOT_OPACITY(item);
        return o !== "1" ? "opacity: " + o + ";" : "";
    },

    GET_DEGRADATION_MAIN: function (item) {
        if (item.type === "item_weapon" || item.maxDegradation === 0 || item.degradation === undefined || item.degradation === null || TIME_NOW === undefined) return "";
        const degradationPercentage = this.GET_ITEM_DEGRADATION_PERCENTAGE(item);
        const color = this.GET_DEGRADATION_COLOR(degradationPercentage);

        return `<br>${LANGUAGE.labels.decay}<span style="color: ${color}">${degradationPercentage.toFixed(0)}%</span>`;
    },

    GET_DEGRADATION_CUSTOM: function (item) {
        if (item.type === "item_weapon" || item.maxDegradation === 0 || item.degradation === undefined || item.degradation === null || item.percentage === undefined || item.percentage === null) return "";
        const degradationPercentage = item.percentage;
        const color = this.GET_DEGRADATION_COLOR(degradationPercentage);
        return `<br>${LANGUAGE.labels.decay}<span style="color: ${color}">${degradationPercentage.toFixed(0)}%</span>`;
    },

    IS_ITEM_EXCLUDED_FROM_RARITY_FEATURES: function (item) {
        if (item.type === "item_weapon") return true;
        if (item.type === "item_money" || item.type === "item_gold" || item.type === "item_rol") return true;
        return false;
    },

    IS_ITEM_ELIGIBLE_FOR_RARITY_SLOT_VISUAL: function (item) {
        if (!item) return false;
        return !this.IS_ITEM_EXCLUDED_FROM_RARITY_FEATURES(item);
    },

    GET_ITEM_RARITY_SLOT_STYLE_SETTING: function () {
        return String(Config.ItemRaritySlotStyle).trim().toLowerCase();
    },

    GET_ITEM_RARITY_ID_FOR_SLOT_VISUAL: function (item) {
        if (!this.IS_ITEM_ELIGIBLE_FOR_RARITY_SLOT_VISUAL(item)) return 0;
        const id = this.GET_ITEM_RARITY_ID(item);
        if (id >= 2 && id <= 5) return id;

        return 0;
    },

    SHOULD_SHOW_RARITY_IN_TOOLTIP: function (item) {
        if (!this.IS_ITEM_ELIGIBLE_FOR_RARITY_SLOT_VISUAL(item)) return false;
        const id = this.GET_ITEM_RARITY_ID(item);

        return id >= 1 && id <= 5;
    },

    SHOULD_APPLY_RARITY_SLOT_CHROME: function (item) {
        if (!this.IS_ITEM_ELIGIBLE_FOR_RARITY_SLOT_VISUAL(item)) return false;
        if (this.GET_ITEM_RARITY_SLOT_STYLE_SETTING() === "none") return false;

        const vid = this.GET_ITEM_RARITY_ID_FOR_SLOT_VISUAL(item);
        return vid >= 2 && vid <= 5;
    },

    GET_ITEM_RARITY_ID: function (item) {
        if (!item) return 0;
        let v = item.rarity;
        if (v == null && item.metadata && item.metadata.rarity != null) v = item.metadata.rarity;
        const n = Number(v);
        if (!Number.isFinite(n) || n < 1) return 0;

        return Math.min(5, Math.max(1, Math.floor(n)));
    },

    GET_RARITY_LABEL_TEXT: function (id) {
        if (id < 1 || id > 5) return "";
        const key = RARITY_THEME[id].labelKey;
        const fromLang = LANGUAGE && LANGUAGE.labels && LANGUAGE.labels[key];

        return (fromLang.length) ? fromLang : RARITY_FALLBACK_LABELS[id];
    },

    APPLY_RARITY_SLOT_CLASSES: function ($el, item) {
        if (!$el || !$el.length) return;
        const el = $el[0];

        for (let i = 1; i <= 5; i++) {
            el.classList.remove("item--rarity-" + i);
        }

        el.classList.remove("item--rarity-style-border", "item--rarity-style-bg", "item--rarity-style-bgimg");
        el.style.removeProperty("--rarity-slot-img");
        el.style.removeProperty("background-image");
        if (!this.SHOULD_APPLY_RARITY_SLOT_CHROME(item)) return;

        const id = this.GET_ITEM_RARITY_ID_FOR_SLOT_VISUAL(item);
        if (!id) return;

        const style = this.GET_ITEM_RARITY_SLOT_STYLE_SETTING();
        $el.addClass("item--rarity-" + id);
        if (style === "border")
            $el.addClass("item--rarity-style-border");
        else if (style === "background")
            $el.addClass("item--rarity-style-bg");
        else if (style === "background-img") {
            const name = RARITY_SLOT_IMAGE_NAME[id];
            if (!name) {
                el.classList.remove("item--rarity-" + id);
                return;
            }
            $el.addClass("item--rarity-style-bgimg");
            el.style.setProperty("--rarity-slot-img", `url("../img/slot-${name}.png")`);
        }
    },

    BUILD_INVENTORY_DRAG_HELPER: function (element, event) {
        const $el = $(element);
        const $clone = $el.clone();
        const item = $el.data("item");
        const alt = !!(event && (event.altKey || event.originalEvent?.altKey));

        if (alt && item.type !== "item_weapon" && Number(item.count) > 1) {
            const split = Math.ceil(Number(item.count) / 2);
            const $span = $clone.find(".count span");
            if ($span.length) {
                $span.text(String(split));
            } else {
                $clone.find(".count").hide();
            }
        }
        return $clone;
    },

    INVENTORY_SLOT_BACKGROUND_STYLE: function (iconImageLayer, iconW, iconH, extraCss) {
        const iconLayerRaw = iconImageLayer == null ? "" : String(iconImageLayer).trim();
        const iconLayer = iconLayerRaw.replace(/;+\s*$/, "");
        const extra = extraCss && String(extraCss).trim() ? String(extraCss).trim() + " " : "";
        const h = iconH != null && String(iconH).trim() !== "" ? String(iconH).trim() : "";
        const firstSize = h ? String(iconW).trim() + " " + h : String(iconW).trim();
        return (
            "background-image: " +
            iconLayer +
            "; background-size: " +
            firstSize +
            "; background-repeat: no-repeat; background-position: center; " +
            extra
        );
    },

    GET_AMMO_TYPE_LABEL: function (ammoKey) {
        const ind = ammoKey == null ? "" : String(ammoKey);
        if (ammolabels && typeof ammolabels === "object" && !Array.isArray(ammolabels) && ammolabels[ind]) {
            return String(ammolabels[ind]);
        }
        return ind || "";
    },

    GET_WEAPON_AMMO_TOOLTIP_ENTRIES: function (item) {
        if (!item || item.type !== "item_weapon") return [];
        const ammo = item.ammo;
        if (ammo == null || Array.isArray(ammo)) return [];

        const rows = [];
        for (const [ind, tab] of Object.entries(ammo)) {
            const n = Number(tab);
            if (!Number.isFinite(n) || n <= 0) continue;
            rows.push({ ind: String(ind), label: this.GET_AMMO_TYPE_LABEL(ind), n });
        }
        return rows;
    },

    GET_WEAPON_AMMO_DISPLAY_COUNT: function (item) {
        if (!item || item.type !== "item_weapon") return 0;
        const ammo = item.ammo;
        if (!ammo || Array.isArray(ammo)) return 0;

        const preferred = item.current_ammo_type != null ? String(item.current_ammo_type) : null;
        if (preferred != null && ammo[preferred]) {
            const n = Number(ammo[preferred]);
            return Number.isFinite(n) ? Math.max(0, Math.floor(n)) : 0;
        }
        const keys = Object.keys(ammo).sort();
        if (!keys.length) return 0;

        const n = Number(ammo[keys[0]]);
        return Number.isFinite(n) ? Math.max(0, Math.floor(n)) : 0;
    },

    // ui.html ships with its text baked in, in English. data-lang replaces the
    // text, data-lang-title the tooltip and data-lang-aria the screen reader
    // label. Keys resolve against LANGUAGE.ui first, then the flat LANGUAGE
    // table, so an entry that already exists there is not duplicated.
    RESOLVE_STATIC_LANG: function (key) {
        if (!key || !LANGUAGE) return null;
        const value = LANGUAGE.ui?.[key] ?? LANGUAGE[key];
        return (value == null || value === "") ? null : String(value);
    },

    APPLY_STATIC_LANG: function () {
        const targets = [
            ["data-lang", function (el, text) { el.textContent = text; }],
            ["data-lang-title", function (el, text) { el.title = text; }],
            ["data-lang-aria", function (el, text) { el.setAttribute("aria-label", text); }],
        ];

        for (let i = 0; i < targets.length; i++) {
            const attribute = targets[i][0];
            const apply = targets[i][1];

            document.querySelectorAll("[" + attribute + "]").forEach(function (el) {
                const text = UTILS.RESOLVE_STATIC_LANG(el.getAttribute(attribute));
                if (text !== null) apply(el, text);
            });
        }
    },

}

const INVENTORY = {
    WEAPON: {
        SHOW_AMMO_UI: function (item) {
            return this.GET_CLIP_SIZE(item) > 0;
        },

        GET_AMMO_ICON: function (item) {
            if (!this.SHOW_AMMO_UI(item)) return "";
            const text = this.GET_AMMO_COUNT(item);
            const img = "img/ammo.png";
            return (
                '<div class="weapon-ammo-count">' +
                '<img class="weapon-ammo-count-icon" src="' + img + '" alt="" loading="lazy" ' +
                'onerror="this.onerror=null;this.src="' + img + '";"/>' +
                '<span class="weapon-ammo-count-text">' +
                UTILS.ESCAPE_HTML(text) +
                "</span></div>"
            );
        },

        GET_CLIP_SIZE: function (item) {
            if (!item || item.type !== "item_weapon") return 0;
            const v = item.defaultClipSize;
            const n = Number(v);
            return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
        },

        GET_AMMO_COUNT: function (item) {
            const cur = UTILS.GET_WEAPON_AMMO_DISPLAY_COUNT(item);
            const clip = this.GET_CLIP_SIZE(item);
            if (clip > 0) return cur + "/" + clip;
            return String(cur);
        },
    },

    DISABLE: async function (ms) {
        disabled = true;
        await new Promise(resolve => setTimeout(resolve, ms));
        disabled = false;
    },

    SEND_GIVE: function (data) {
        if (!data || !data.type) return;
        secureCallbackToNui("vorp_inventory", "GiveItem", { data: data });
    },

    INIT_MOUSE_SOUND_HOVER: function () {
        if (isOpen) {
            const div = document.getElementById("inventoryElement");

            div.onmouseover = function () {
                $.post(`https://${GetParentResourceName()}/sound`);
            };
        }
    },

    TOOLTIP: {

        ADD_AMMO: function ($root, item, opts) {
            opts = opts || {};
            if (!item || item.type !== "item_weapon") return;
            if (!INVENTORY.WEAPON.SHOW_AMMO_UI(item)) return;

            const entries = UTILS.GET_WEAPON_AMMO_TOOLTIP_ENTRIES(item);
            const noAmmoLabel = LANGUAGE.labels?.noAmmoInWeapon;
            const $ammo = $("<div/>").addClass("tooltip-rich-ammo tooltip-rich-ammo--weapon");
            if (opts.inline) {
                $ammo.addClass("tooltip-rich-ammo--in-stats");
            }

            const clip = INVENTORY.WEAPON.GET_CLIP_SIZE(item);
            if (entries.length) {
                for (let i = 0; i < entries.length; i++) {
                    const e = entries[i];
                    const line = clip > 0 ? e.label + " " + e.n + "/" + clip : e.label + " " + e.n;
                    const $row = $("<div/>").addClass("tooltip-rich-ammo-row");
                    $row.append($("<span/>").addClass("tooltip-rich-ammo-line").text(line));
                    $ammo.append($row);
                }
            } else {
                const $row = $("<div/>").addClass("tooltip-rich-ammo-row");
                $row.append($("<span/>").addClass("tooltip-rich-ammo-line").text(noAmmoLabel));
                $ammo.append($row);
            }

            const target = opts.target || $root;
            target.append($ammo);
        },

        ADD_WEAPON_STATUS: function ($root, item, isCustom) {
            if (!item || item.type !== "item_weapon") return;

            const barsHtml = this.WEAPON_LIVE_STATUS_BARS(item, isCustom);
            if (!barsHtml) return;

            const title = LANGUAGE.labels?.weaponStatus ?? "Weapon Status";
            const $section = $("<div/>").addClass("tooltip-rich-weapon-status");
            $section.append($("<div/>").addClass("tooltip-rich-weapon-status-title").text(title));
            $section.append(barsHtml);
            $root.append($section);
        },

        ADD_WEAPON: function (item) {
            if (!item || item.type !== "item_weapon") return "";
            if (!INVENTORY.WEAPON.SHOW_AMMO_UI(item)) return "";

            const entries = UTILS.GET_WEAPON_AMMO_TOOLTIP_ENTRIES(item);
            const ammoLab = LANGUAGE.labels?.ammo;
            const noAmmoLabel = LANGUAGE.labels?.noAmmoInWeapon;
            if (!entries.length)
                return "<br>" + UTILS.ESCAPE_HTML(noAmmoLabel);

            const clip = INVENTORY.WEAPON.GET_CLIP_SIZE(item);
            const lines = entries.map(function (e) {
                if (clip > 0)
                    return UTILS.ESCAPE_HTML(e.label) + " " + UTILS.ESCAPE_HTML(String(e.n)) + "/" + UTILS.ESCAPE_HTML(String(clip));

                return UTILS.ESCAPE_HTML(e.label) + " " + UTILS.ESCAPE_HTML(String(e.n));
            });

            return "<br>" + UTILS.ESCAPE_HTML(ammoLab) + "<br>" + lines.join("<br>");
        },


        WEAPON_LIVE_STATUS_BARS: function (item, isCustom) {
            if (!item || item.type !== "item_weapon" || isCustom) return "";
            if (item.canDegrade === false) return "";
            if (!item.used && !item.used2) return "";

            const s = item.weaponLiveStatus;
            if (!s || typeof s !== "object") return "";
            const L = LANGUAGE.labels || {};

            const rows = [
                { key: "degradation", lab: L.weaponWear },
                { key: "damage", lab: L.weaponDamage },
                { key: "dirt", lab: L.weaponDirt },
                { key: "soot", lab: L.weaponSoot },
            ];


            let rowsHtml = "";
            for (let i = 0; i < rows.length; i++) {
                const raw = Number(s[rows[i].key]);
                const badness = Number.isFinite(raw) ? Math.max(0, Math.min(1, raw)) : 0;
                const condition = 1 - badness;
                const pct = (condition * 100).toFixed(0) + "%";
                const color = condition < 0.2 ? "#e74c3c" : "#ffffff";
                rowsHtml +=
                    "<div class=\"weapon-live-stat-row\"><div class=\"weapon-live-stat-bar-outer\"><div class=\"weapon-live-stat-bar-inner\" style=\"width:" +
                    pct +
                    ";background-color:" +
                    color +
                    ';\"></div></div><span class=\"tooltip-rich-stat-label weapon-live-stat-label\">' +
                    UTILS.ESCAPE_HTML(rows[i].lab) +
                    "</span></div>";
            }
            return rowsHtml ? '<div class="weapon-live-stat-bars">' + rowsHtml + "</div>" : "";
        },

        SETUP_CONTENT: function ($root, item, opts) {
            opts = opts || {};
            const isCustom = !!opts.isCustom;
            const group = Number(opts.group != null ? opts.group : (item.group != null ? item.group : 1));
            const count = opts.count != null ? opts.count : (item.count != null ? item.count : 1);
            const limit = opts.limit != null ? opts.limit : item.limit;

            const meta = UTILS.GET_ITEM_METADATA_INFO(item, isCustom);
            const wCount = item.type === "item_weapon" ? 1 : count;
            const wp = this.FORMAT_WEIGHT(meta.weight, wCount);
            const weightStr = `<br><span class="tooltip-rich-stat-label">${UTILS.ESCAPE_HTML(wp.label)}</span> <span class="tooltip-rich-stat-value">${UTILS.ESCAPE_HTML(wp.value)}</span>`;
            const groupKey = UTILS.GET_GROUP_KEY(group);
            const decay = meta.degradation || "";

            const thumbSrc = "img/items/" + UTILS.SAFE_ITEM_IMAGE(meta.image) + ".png";
            const $row = $("<div/>").addClass("tooltip-rich-row");
            const $img = $("<img/>").addClass("tooltip-rich-thumb").attr({ src: thumbSrc, alt: "" });
            $img.on("error", function () {
                this.src = "img/items/placeholder.png";
            });
            $row.append($img);

            const $meta = $("<div/>").addClass("tooltip-rich-meta");
            if (meta.label) {
                $meta.append($("<div/>").addClass("tooltip-rich-label").text(meta.label));
            }
            if (meta.description) {
                $meta.append($("<div/>").addClass("tooltip-rich-desc").html(meta.description));
            }
            $row.append($meta);
            $root.append($row);

            const $stats = $("<div/>").addClass("tooltip-rich-stats");
            let statsHtml = "";
            if (group > 1 && groupKey && window.ITEM_GROUPS && window.ITEM_GROUPS[groupKey]) {
                const groupImg = window.ITEM_GROUPS[groupKey].img;
                statsHtml += `<img class="tooltip-rich-group" src="img/itemtypes/${UTILS.ESCAPE_HTML(groupImg)}" alt=""> `;
            }
            if (limit != null && limit !== "" && Number(limit) !== -1) {
                const limLab = LANGUAGE.labels?.limit || "Limit ";
                const limVal = count != null && count !== "" ? `${String(count)}/${String(limit)}` : String(limit);
                statsHtml += `<span class="tooltip-rich-stat-label">${UTILS.ESCAPE_HTML(limLab.trim())}</span> <span class="tooltip-rich-stat-value">${UTILS.ESCAPE_HTML(limVal)}</span>`;
            }
            statsHtml += weightStr + (meta.durability || "") + decay;
            if (item.type === "item_weapon" && item.serial_number) {
                const serialLab = LANGUAGE.labels?.serial ?? "Serial";
                statsHtml +=
                    "<br>" +
                    `<span class="tooltip-rich-stat-label">${UTILS.ESCAPE_HTML(serialLab)}</span> <span class="tooltip-rich-stat-value">${UTILS.ESCAPE_HTML(String(item.serial_number))}</span>`;
            }
            $stats.html(statsHtml);
            if (item.type === "item_weapon") {
                this.ADD_AMMO($stats, item, { inline: true });
            }
            $root.append($stats);

            this.ADD_WEAPON_STATUS($root, item, isCustom);

            if (UTILS.SHOULD_SHOW_RARITY_IN_TOOLTIP(item)) {
                const rid = UTILS.GET_ITEM_RARITY_ID(item);
                const rlabel = UTILS.GET_RARITY_LABEL_TEXT(rid);
                const theme = RARITY_THEME[rid];
                if (rlabel && theme) {
                    $root.append(
                        $("<div/>")
                            .addClass("tooltip-rich-rarity tooltip-rich-rarity--after-stats")
                            .text(rlabel)
                            .css("color", theme.border)
                    );
                }
            }

            if (item.metadata && item.metadata.tooltip) {
                $root.append(
                    $("<div/>")
                        .addClass("tooltip-rich-metadata")
                        .html(String(item.metadata.tooltip))
                );
            }

            let instructionText = "";
            if (item.metadata && item.metadata.instruction != null) {
                const fromMeta = String(item.metadata.instruction).trim();
                if (fromMeta !== "") instructionText = fromMeta;
            }
            if (!instructionText && item.instruction != null) {
                const fromItem = String(item.instruction).trim();
                if (fromItem !== "") instructionText = fromItem;
            }
            if (instructionText) {
                $root.append(
                    $("<div/>")
                        .addClass("tooltip-rich-instruction")
                        .html(UTILS.ESCAPE_HTML(instructionText).replace(/\n/g, "<br>"))
                );
            }
        },

        APPEND_HEADER: function ($root, imageKey, title, desc, $afterLabel) {
            const thumbSrc = "img/" + UTILS.SAFE_ITEM_IMAGE(imageKey) + ".png";
            const $row = $("<div/>").addClass("tooltip-rich-row");
            const $img = $("<img/>").addClass("tooltip-rich-thumb").attr({ src: thumbSrc, alt: "" });
            $img.on("error", function () {
                this.src = "img/items/placeholder.png";
            });

            $row.append($img);
            const $meta = $("<div/>").addClass("tooltip-rich-meta");
            if (title)
                $meta.append($("<div/>").addClass("tooltip-rich-label").text(title));
            if ($afterLabel && $afterLabel.length)
                $meta.append($afterLabel);
            if (desc)
                $meta.append($("<div/>").addClass("tooltip-rich-desc").html(desc));

            $row.append($meta);
            $root.append($row);
        },


        APPEND_HUD_STRIP: function ($root, title, $body) {
            const $strip = $("<div/>").addClass("tooltip-rich-hud-strip");
            if (title) {
                $strip.append($("<div/>").addClass("tooltip-rich-label").text(title));
            }
            if ($body && $body.length) {
                $strip.append($body);
            }
            $root.append($strip);
        },

        ADD_GUNBELT: function ($root) {
            const title = LANGUAGE.gunbeltlabel;
            const $amount = $("<div/>").addClass("tooltip-rich-hud-amount");
            let any = false;
            if (allplayerammo) {
                for (const [ind, tab] of Object.entries(allplayerammo)) {
                    const n = Number(tab);
                    if (!n || n <= 0) continue;
                    any = true;
                    const label = UTILS.GET_AMMO_TYPE_LABEL(ind);
                    const line = label + " " + n;
                    const $row = $("<div/>").addClass("tooltip-rich-ammo-row");
                    $row.append($("<span/>").addClass("tooltip-rich-ammo-line").text(line));
                    $amount.append($row);
                }
            }

            if (!any) {
                $amount.append($("<div/>").addClass("tooltip-rich-ammo-empty").text(LANGUAGE.empty || ""));
            }
            this.APPEND_HUD_STRIP($root, title, $amount);
        },

        ADD_MONEY: function ($root) {
            const title = LANGUAGE.inventorymoneylabel || "";
            const amount = ($("#money-value").text() || "").trim();
            const $amount = $("<div/>").addClass("tooltip-rich-hud-amount").text(amount || "—");
            this.APPEND_HUD_STRIP($root, title, $amount);
        },

        ADD_GOLD: function ($root) {
            const title = LANGUAGE.inventorygoldlabel;
            const amount = ($("#gold-value").text()).trim();
            const $amount = $("<div/>").addClass("tooltip-rich-hud-amount").text(amount || "—");
            this.APPEND_HUD_STRIP($root, title, $amount);
        },

        ADD_ROLL: function ($root) {
            const title = LANGUAGE.inventoryrolllabel || "Roll";
            const amount = ($("#rol-value").text() || "").trim();
            const $amount = $("<div/>").addClass("tooltip-rich-hud-amount").text(amount || "—");
            this.APPEND_HUD_STRIP($root, title, $amount);
        },

        GET_CONTENT: function (image, groupKey, group, limit, weight, degradation, tooltipData, count, durability) {
            const groupImg = groupKey ? window.ITEM_GROUPS[groupKey].img : 'satchel_nav_all.png';
            let limitLabel = "";
            if (limit != null && limit !== "" && Number(limit) !== -1) {
                const limLab = LANGUAGE.labels?.limit || "Limit ";
                const cnt = count != null && count !== "" ? String(count) : "";
                limitLabel = limLab + (cnt ? cnt + "/" : "") + String(limit);
            }
            const dur = durability != null && durability !== "" ? durability : "";
            const tooltipContent = group > 1 ? `<img src="img/itemtypes/${groupImg}"> ${limitLabel + weight + dur + degradation + tooltipData}` : `${limitLabel}${weight}${dur}${degradation}${tooltipData}`;
            const url = imageCache[image];
            return { tooltipContent, url };
        },

        APPLY_LOCATION: function ($tooltip, $anchor, pointerEvent) {
            const mode = Config.TooltipPlacement;
            const isCompactHud = $tooltip && $tooltip.length && $tooltip.hasClass("tooltip--rich-compact-hud");
            if (isCompactHud && pointerEvent) {
                const pe = pointerEvent.originalEvent || pointerEvent;
                if (pe.clientX != null && pe.clientY != null) {
                    requestAnimationFrame(() => {
                        requestAnimationFrame(() => {
                            this.STATIC_ITEMS($tooltip, pointerEvent);
                        });
                    });
                    return;
                }
            }
            if (mode === "dock" && !this.IS_STATIC_ANCHOR($anchor, $tooltip)) {
                requestAnimationFrame(() => {
                    requestAnimationFrame(() => {
                        this.ADD_CENTER_POSITION($tooltip);
                    });
                });
                return;
            }
            this.POSITION_NEAR_ANCHOR($tooltip, $anchor);
        },

        ADD_CENTER_POSITION: function ($tooltip) {
            const margin = 12;
            const $main = $("#inventoryElement");
            if (!$main.length) return;

            const mainRect = $main[0].getBoundingClientRect();
            const $second = $("#secondInventoryElement");
            const secondEl = $second.length ? $second[0] : null;
            const secRect = secondEl ? secondEl.getBoundingClientRect() : null;
            const secondVisible = secondEl && $second.is(":visible") && secRect && secRect.width > 0 && secRect.height > 0;

            const tw = $tooltip.outerWidth() || 0;
            const th = $tooltip.outerHeight() || 0;

            let left;
            if (secondVisible) {
                const gapCenter = (mainRect.right + secRect.left) / 2;
                left = gapCenter - tw / 2;
            } else {
                left = mainRect.right + margin;
            }
            let top = mainRect.top + (mainRect.height - th) / 2;

            const vw = window.innerWidth;
            const vh = window.innerHeight;
            left = Math.max(margin, Math.min(vw - tw - margin, left));
            top = Math.max(margin, Math.min(vh - th - margin, top));

            $tooltip.addClass("tooltip--dock");
            $tooltip.css({
                position: "fixed",
                left: Math.round(left),
                top: Math.round(top),
                display: "block",
            });
        },

        STATIC_ITEMS: function ($tooltip, ev) {
            const src = ev && (ev.originalEvent || ev);
            const cx = src && src.clientX;
            const cy = src && src.clientY;
            if (cx == null || cy == null) return;

            $tooltip.removeClass("tooltip--dock");
            const pad = 14;
            const tw = $tooltip.outerWidth() || 180;
            const th = $tooltip.outerHeight() || 48;
            let left = cx + pad;
            let top = cy - th / 2;
            const vw = window.innerWidth;
            const vh = window.innerHeight;

            if (left + tw > vw - 8) left = Math.max(8, cx - tw - pad);
            if (top < 8) top = 8;
            if (top + th > vh - 8) top = Math.max(8, vh - th - 8);

            $tooltip.css({
                position: "fixed",
                left: Math.round(left),
                top: Math.round(top),
                display: "block",
                margin: 0,
                zIndex: 99999,
            });
        },

        POSITION_NEAR_ANCHOR: function ($tooltip, $anchor) {
            const el = $anchor && $anchor[0];
            if (!el || typeof el.getBoundingClientRect !== "function") return;

            $tooltip.removeClass("tooltip--dock");
            const rect = el.getBoundingClientRect();
            const pad = 14;
            const tw = $tooltip.outerWidth() || 180;
            const th = $tooltip.outerHeight() || 48;
            let left = rect.right + pad;
            let top = rect.top + (rect.height - th) / 2;
            const vw = window.innerWidth;
            const vh = window.innerHeight;

            if (left + tw > vw - 8) {
                left = Math.max(8, rect.left - tw - pad);
            }
            if (top < 8) top = 8;
            if (top + th > vh - 8) top = Math.max(8, vh - th - 8);

            $tooltip.css({
                position: "fixed",
                left: Math.round(left),
                top: Math.round(top),
                display: "block",
                margin: 0,
                zIndex: 99999,
            });
        },

        IS_STATIC_ANCHOR: function ($anchor, $tooltip) {
            if ($tooltip && $tooltip.length && $tooltip.hasClass("tooltip--rich-compact-hud")) return true;
            if (!$anchor || !$anchor.length)
                return false;

            if ($anchor.closest("#inventoryFixedSlotsStrip").length)
                return true;

            const id = $anchor.attr("id") || "";
            return (
                id === "item-money" ||
                id === "item-gold" ||
                id === "item-gunbelt" ||
                id === "item-rol"
            );
        },

        FORMAT_WEIGHT: function (weight, count) {
            const num = weight != null ? (weight * count).toFixed(2) : (count / 4).toFixed(2);
            const measure = Config.WeightMeasure != null ? String(Config.WeightMeasure) : "kg";

            return {
                label: LANGUAGE.labels?.weight != null ? String(LANGUAGE.labels.weight) : "Weight",
                value: `${num} ${measure}`,
            };
        },
    },

    DIALOG: function (item, type, action, isAll) {
        let dropCallback = null;

        if (action === "dropAdvanced") {
            dropCallback = "DropItemAdvanced";
        } else if (action === "drop") {
            if (type === "item_money") {
                dropCallback = "DropItemMoney";
            } else if (type === "item_gold") {
                dropCallback = "DropItemGold";
            } else if (type === "item_rol") {
                dropCallback = "DropItemRoll";
            } else if (type === "item_standard") {
                dropCallback = "DropItemStandard";
            }
        }

        if (dropCallback) {
            const postDrop = function (payload) {
                const outgoing = action === "dropAdvanced" ? { ...payload, type } : payload;
                secureCallbackToNui("vorp_inventory", dropCallback, outgoing);
            };

            if (item.count && item.count === 1 && type === "item_standard") {
                postDrop({
                    item: item.name,
                    id: item.id,
                    number: 1,
                    metadata: item.metadata,
                    degradation: item.degradation,
                });
                return;
            }

            if (isAll) {
                let countNum;
                if (type === "item_money") {
                    countNum = UTILS.PARSE_HUD_AMOUNT($("#money-value"));
                } else if (type === "item_gold") {
                    countNum = UTILS.PARSE_HUD_AMOUNT($("#gold-value"));
                } else if (type === "item_rol") {
                    countNum = UTILS.PARSE_HUD_AMOUNT($("#rol-value"));
                } else {
                    countNum = parseInt(String(item.count), 10);
                }
                if (type === "item_money" || type === "item_gold" || type === "item_rol") {
                    if (!(Number.isFinite(countNum) && countNum > 0))
                        return;

                    postDrop({ number: countNum });
                    return;
                }
                if (!Number.isFinite(countNum)) {
                    countNum = item.count;
                }
                postDrop({
                    item: item.name,
                    id: item.id,
                    number: countNum,
                    metadata: item.metadata,
                    degradation: item.degradation,
                });
                return;
            }

            dialog.prompt({
                title: LANGUAGE.prompttitle,
                button: LANGUAGE.promptaccept,
                required: false,
                item: item.name,
                type: type,
                input: {
                    type: "number",
                    autofocus: "true",
                },

                validate: function (value, itemNameField, dlgType) {
                    if (!value || value <= 0) {
                        dialog.close();
                        return;
                    }

                    if (dlgType !== "item_money" && dlgType !== "item_gold" && dlgType !== "item_rol") {
                        if (!UTILS.IS_INT(value))
                            return;

                    }

                    const qty = (dlgType === "item_money" || dlgType === "item_gold" || dlgType === "item_rol")
                        ? parseFloat(String(value).replace(",", "."))
                        : parseInt(String(value), 10);

                    if (!Number.isFinite(qty) || qty <= 0) {
                        dialog.close();
                        return;
                    }

                    if (dlgType === "item_money" || dlgType === "item_gold" || dlgType === "item_rol") {
                        postDrop({ number: qty });
                    } else {
                        postDrop({
                            item: item.name,
                            id: item.id,
                            number: qty,
                            metadata: item.metadata,
                            degradation: item.degradation,
                        });
                    }

                    return true;
                },
            });
        }
        if (action === "give") {

            if (type === "item_money" || type === "item_gold") {
                const max = type === "item_money"
                    ? UTILS.PARSE_HUD_AMOUNT($("#money-value"))
                    : UTILS.PARSE_HUD_AMOUNT($("#gold-value"));
                if (!(max > 0)) return;

                if (isAll) {
                    INVENTORY.SEND_GIVE({
                        type: type,
                        id: 0,
                        count: max,
                    });
                    return;
                }

                dialog.prompt({
                    title: LANGUAGE.prompttitle,
                    button: LANGUAGE.promptaccept,
                    required: true,
                    item: item.name,
                    type: type,
                    input: {
                        type: "number",
                        autofocus: "true",
                    },
                    validate: function (value, itemNameField, dlgType) {
                        const v = parseFloat(String(value).replace(",", "."));
                        if (!(v > 0)) {
                            dialog.close();
                            return;
                        }
                        if (v > max) {
                            dialog.close();
                            return;
                        }
                        INVENTORY.SEND_GIVE({
                            type: dlgType,
                            id: 0,
                            count: v,
                        });
                        return true;
                    },
                });
                return;
            }

            if (type === "item_standard") {
                if (item.count === 1) {
                    INVENTORY.SEND_GIVE({
                        type: "item_standard",
                        item: item.name,
                        id: item.id,
                        count: 1,
                        metadata: item.metadata,
                    });
                    return;
                }
                if (item.count && item.count > 1) {
                    dialog.prompt({
                        title: LANGUAGE.prompttitle,
                        button: LANGUAGE.promptaccept,
                        required: false,
                        item: item,
                        type: type,
                        input: {
                            type: "number",
                            autofocus: "true",
                        },
                        validate: function (value, item, type) {
                            if (!value || value <= 0) {
                                dialog.close();
                                return;
                            }

                            if (!UTILS.IS_INT(value)) {
                                dialog.close();
                                return;
                            }

                            const giveQty = parseInt(String(value), 10);

                            INVENTORY.SEND_GIVE({
                                type: type,
                                item: item.name,
                                id: item.id,
                                count: giveQty,
                                metadata: item.metadata,
                            });

                            return true;
                        },
                    });
                }
            }
        }
    },

    CLOSE_INPUT: function () {
        $("#disabler").hide();
    },

    CLOSE: function () {
        INVENTORY.MAIN.CLEAR_INV_SORT();
        $("body").removeClass("inventory-open");
        $('.tooltip').remove();
        $("#inv-controls-hint").hide();
        WEAPON_ATTACHMENTS.CLOSE();
        $.post(`https://${GetParentResourceName()}/NUIFocusOff`, JSON.stringify({}));
        isOpen = false;
    }
}

