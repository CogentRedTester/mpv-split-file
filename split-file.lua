--[[
    Splits a file into multiple files on each chapter using ffmpeg.
    Designed for splitting youtube music compilations into individual files.

    Available at: https://github.com/CogentRedTester/mpv-split-file/tree/master
]]

local mp = require "mp"
local msg = require "mp.msg"
local utils = require "mp.utils"

local function execute(o)
    local args = {"ffmpeg", "-y", "-i", o.input, "-ss", tostring(o.start), "-to", tostring(o.finish), "-c", "copy", "-map_chapters", "-1"}

    --dynamically insert all of the custom metadata
    for key, value in pairs(o.metadata) do
        table.insert(args, "-metadata")
        table.insert(args, string.format("%s=%s", key, value))
    end
    table.insert(args, o.output)

    msg.debug(table.unpack(args))

    local cmd = mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = args
    }, function(_, result)
        if result.status == 0 then return msg.info("Successfully split", o.output) end

        msg.error(string.format("Exit code %d: Failed to split file '%s'", result.status, o.output))
    end)
    return cmd
end

local function main(directory)
    msg.info("Splitting file into pieces on chapters")

    local file = mp.get_property("path")
    local title = mp.get_property("media-title")
    local ext = file:match("%.(%w+)$")
    local chapters = mp.get_property_native("chapter-list", {})

    if not file then return msg.error("could not get currently playing file") end
    if not next(chapters) then return msg.error("no chapters found") end

    --if the directory is not set, then save the files inside the directory of the currently playing file
    if not directory then directory = file:match("^(.+[/\\])[^/\\]+$") or "" end
    directory = mp.command_native({"expand-path", directory})
    directory = utils.join_path(mp.get_property("working-directory", ""), directory)

    if not directory:find("[/\\]$") then directory = directory..'/' end

    msg.info("Saving files to:", directory)
    msg.info("Saving as format:", ext)
    
    local num_digits = #chapters >= 99 and "3" or "2"
    local output_num = 1

    local function format_output(name)
        local name = ("%0"..num_digits.."d - %s.%s"):format(output_num, name or "", ext)
        output_num = output_num + 1
        return directory..name
    end

    --split any parts of the file before the first chapter (if any exist)
    if chapters[1].time > 0 then
        execute({
            input = file,
            start = 0,
            finish = chapters[1].time,
            metadata = {
                track = output_num,
                album = title
            },
            output = format_output(chapters[1].title)
        })
    end

    --split all the sections between chapters
    for i = 1, #chapters-1, 1 do
        execute({
            input = file,
            start = chapters[i].time,
            finish = chapters[i+1].time,
            metadata = {
                title = chapters[i].title,
                track = output_num,
                album = title
            },
            output = format_output(chapters[i].title)
        })
    end

    --split the part of the file after the last chapter
    execute({
        input = file,
        start = chapters[#chapters].time,
        finish = mp.get_property_number("duration", math.huge),
        metadata = {
            title = chapters[#chapters].title,
            track = output_num,
            album = title
        },
        output = format_output(chapters[#chapters].title)
    })
end

mp.register_script_message("split-file", main)
