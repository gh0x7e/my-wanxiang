--[[
    set_schema_lx.lua —— 乱序双拼键位方案快速切换（my-wanxiang 定制版）

    在中文输入状态直接键入以下命令即可切换（看到提示后「重新部署」生效）：

        /lxsq    → 乱序十七          /sqyh    → 十七优化
        /lx20    → 乱序二十          /lx23    → 乱序廿三
        /lx24    → 乱序廿四          /lx26    → 乱序廿六
        /lxsj    → 乱序手机          /yjyh    → 原键优化
        /pinyin  → 全拼（简码映射保持不变）
        /zjf     → 直接辅助          /jjf     → 间接辅助

    同步规则：
      pro / mixedcode / reverse  → 键位方案名（全拼、乱序十七……）
      reverse                    → 笔画组：全拼 hspzn、乱序十七 hslzy、其余 hupvn
      abbrev / phrase            → 简码组（lxsq、sqyh、lx20……）
      english                    → 不随键位变化（仅保证配置存在）

    注意：本脚本与官方 set_schema.lua 功能重叠，请不要同时启用。
]]

-- ======== 配置区 ========

-- 命令 → 键位方案名（wanxiang_algebra_lx 各分组下使用的名字）
local SCHEME_MAP = {
    ["/lxsq"]   = "乱序十七",
    ["/sqyh"]   = "十七优化",
    ["/lx20"]   = "乱序二十",
    ["/lx23"]   = "乱序廿三",
    ["/lx24"]   = "乱序廿四",
    ["/lx26"]   = "乱序廿六",
    ["/lxsj"]   = "乱序手机",
    ["/yjyh"]   = "原键优化",
    ["/pinyin"] = "全拼",
}

-- 键位方案 → 简码组（abbrev / phrase 使用；全拼没有对应组，保持不变）
local JIAN_MAP = {
    ["乱序十七"] = "lxsq",
    ["十七优化"] = "sqyh",
    ["乱序二十"] = "lx20",
    ["乱序廿三"] = "lx23",
    ["乱序廿四"] = "lx24",
    ["乱序廿六"] = "lx26",
    ["乱序手机"] = "lxsj",
    ["原键优化"] = "yjyh",
}

-- 允许被替换掉的方案名（含官方旧名字，便于迁移官方遗留配置）
local SCHEME_NAMES = {
    "全拼",
    "乱序十七", "十七优化", "乱序二十", "乱序廿三",
    "乱序廿四", "乱序廿六", "乱序手机", "原键优化",
    -- 官方旧名
    "自然码", "自然龙", "小鹤双拼", "搜狗双拼", "微软双拼",
    "智能ABC", "紫光双拼", "拼音加加", "国标双拼",
    "蓝天双拼", "汉心龙", "大牛双拼", "首道双拼", "乱序17",
}

-- 已知笔画组名字（切换时统一改掉）
local STROKE_NAMES = {
    hspzn = true, hslzy = true, hulvy = true, hspvy = true, hupvn = true,
}

-- 简码相关的标记（abbrev / phrase 沿用的组名）
local JIAN_TOKENS = {
    lxsq = true, sqyh = true, lxsj = true, yjyh = true,
    ["26jian"] = true, ["18jian"] = true, ["14jian"] = true,
}

-- 官方遗留的 26jian / 18jian / 14jian 引用（乱序版无此分组）
local OLD_JIAN = { "26jian", "18jian", "14jian" }

-- 各文件需要处理的引用类型（english 不随键位变化，仅保证配置存在）
local SCHEME_FILES = {
    ["wanxiang_pro.custom.yaml"] = true,
    ["wanxiang_mixedcode.custom.yaml"] = true,
    ["wanxiang_reverse.custom.yaml"] = true,
}
local STROKE_FILES = {
    ["wanxiang_reverse.custom.yaml"] = true,
}
local JIAN_FILES = {
    ["wanxiang_abbrev.custom.yaml"] = true,
    ["wanxiang_phrase.custom.yaml"] = true,
}

-- ======== 工具函数 ========

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- 与官方 set_schema.lua 一致的复制方式（二进制，原样拷贝）
local function copy_file(src, dest)
    local fi = io.open(src, "rb")
    if not fi then
        return false
    end

    local content = fi:read("*a")
    fi:close()

    local fo = io.open(dest, "wb")
    if not fo then
        return false
    end

    fo:write(content)
    fo:close()
    return true
end

-- 参照官方：由当前方案决定主配置文件名（本分发仅 wanxiang_pro）
local function get_scheme_info(env)
    local schema_id = env.engine.schema.schema_id or ""

    if schema_id == "wanxiang_pro" then
        return "pro", "wanxiang_pro.custom.yaml"
    end

    return nil, nil
end

local function is_scheme_name(name)
    for _, v in ipairs(SCHEME_NAMES) do
        if name == v then
            return true
        end
    end
    return false
end

local function is_jian_token(name)
    return JIAN_TOKENS[name] or name:match("^lx%d+$") ~= nil
end

-- 键位方案 → 笔画组：全拼 hspzn、乱序十七 hslzy、其余 hupvn
local function stroke_group_of(schema)
    if schema == "全拼" then
        return "hspzn"
    elseif schema == "乱序十七" then
        return "hslzy"
    end
    return "hupvn"
end

-- 改写单个配置（参照官方 replace_schema，额外处理简码组 / 笔画组 / 旧引用迁移）
local function replace_schema(file_path, file_name, target_schema)
    local f = io.open(file_path, "r")
    if not f then
        return false
    end

    local content = f:read("*a")
    f:close()

    -- 0) 官方旧引用迁移：wanxiang_algebra: → wanxiang_algebra_lx:
    content = content:gsub("wanxiang_algebra:", "wanxiang_algebra_lx:")

    -- 1) 键位方案名：…/pro/乱序廿三、…/mixed/全拼 之类
    if SCHEME_FILES[file_name] then
        content = content:gsub("(wanxiang_algebra_lx:/[^/%s#]+/)([^%s#/]+)", function(prefix, name)
            if is_scheme_name(name) then
                return prefix .. target_schema
            end
            return prefix .. name
        end)
    end

    -- 2) 笔画组（reverse）：全拼 hspzn、乱序十七 hslzy、其余 hupvn
    if STROKE_FILES[file_name] then
        content = content:gsub("(wanxiang_algebra_lx:/reverse/)([%w]+)", function(prefix, name)
            if STROKE_NAMES[name] then
                return prefix .. stroke_group_of(target_schema)
            end
            return prefix .. name
        end)
    end

    -- 3) 简码组（abbrev / phrase）：跟随键位方案，只改生效行
    local jian = JIAN_MAP[target_schema]
    if JIAN_FILES[file_name] and jian then
        content = content:gsub("(\n[ \t]*%-[ \t]*wanxiang_algebra_lx:/)([%w]+)", function(prefix, name)
            if is_jian_token(name) then
                return prefix .. jian
            end
            return prefix .. name
        end)
    end

    -- 4) 其它文件里官方的 26/18/14jian 行在乱序版无对应分组，注释掉以免部署报错
    if not JIAN_FILES[file_name] then
        for _, token in ipairs(OLD_JIAN) do
            content = content:gsub("(\n[ \t]*)(%-[ \t]*wanxiang_algebra_lx:/" .. token .. ")", "%1#%2")
        end
    end

    local w = io.open(file_path, "w")
    if not w then
        return false
    end

    w:write(content)
    w:close()
    return true
end

-- ======== 主逻辑 ========

local function translator(input, seg, env)
    local profile, main_file = get_scheme_info(env)
    if not profile then
        return
    end

    -- 直接 / 间接辅助（参照官方 set_schema.lua 的处理）
    if input == "/zjf" or input == "/jjf" then
        local target_aux
        if input == "/zjf" then
            target_aux = "直接辅助"
        else
            target_aux = "间接辅助"
        end

        local user_dir = rime_api.get_user_data_dir()
        local p = user_dir .. "/" .. main_file

        if file_exists(p) then
            local f = io.open(p, "r")
            local content = f:read("*a")
            f:close()

            -- 兼容官方旧版引用
            content = content:gsub("wanxiang_algebra:", "wanxiang_algebra_lx:")

            local n1, n2 = 0, 0
            content, n1 = content:gsub("(%-+%s*wanxiang_algebra_lx:/[%w_]+/)直接辅助", "%1" .. target_aux)
            content, n2 = content:gsub("(%-+%s*wanxiang_algebra_lx:/[%w_]+/)间接辅助", "%1" .. target_aux)

            if (n1 + n2) > 0 then
                local w = io.open(p, "w")
                if w then
                    w:write(content)
                    w:close()
                end
                local msg = "当前方案已切换到〔" .. target_aux .. "〕，请重新部署"
                yield(Candidate("switch", seg.start, seg._end, msg, ""))
            else
                yield(Candidate("switch", seg.start, seg._end, "当前配置未找到可切换的条目", ""))
            end
        else
            yield(Candidate("switch", seg.start, seg._end, "未找到当前配置，请先切换双拼方案", ""))
        end
        return
    end

    local target_schema = SCHEME_MAP[input]
    if not target_schema then
        return
    end

    local user_dir = rime_api.get_user_data_dir()
    local shared_dir = rime_api.get_shared_data_dir()
    local dest_main = user_dir .. "/" .. main_file
    local main_exists = file_exists(dest_main)

    local files = {
        "wanxiang_mixedcode.custom.yaml",
        "wanxiang_reverse.custom.yaml",
        "wanxiang_english.custom.yaml",
        "wanxiang_abbrev.custom.yaml",
        "wanxiang_phrase.custom.yaml",
        main_file,
    }

    local touched = 0

    for _, name in ipairs(files) do
        local dest = user_dir .. "/" .. name
        local user_src = user_dir .. "/custom/" .. name
        local shared_src = shared_dir .. "/custom/" .. name

        if file_exists(dest) then
            -- 1. 外部已存在：只改，绝不复制覆盖
            touched = touched + 1
            replace_schema(dest, name, target_schema)
        elseif file_exists(user_src) then
            -- 2. 用户自己放在 custom 里的模板优先
            if copy_file(user_src, dest) then
                touched = touched + 1
                replace_schema(dest, name, target_schema)
            end
        elseif file_exists(shared_src) then
            -- 3. 系统自带模板兜底
            if copy_file(shared_src, dest) then
                touched = touched + 1
                replace_schema(dest, name, target_schema)
            end
        end
    end

    local msg

    if touched == 0 then
        msg = "未找到配置，请先把 custom/ 模板复制到用户目录"
    elseif main_exists then
        msg = "检测到专属配置，已切换到〔" .. target_schema .. "〕，请手动重新部署"
    else
        msg = "已从系统目录构建配置并切换到〔" .. target_schema .. "〕，请手动重新部署"
    end

    yield(Candidate("switch", seg.start, seg._end, msg, ""))
end

return translator
