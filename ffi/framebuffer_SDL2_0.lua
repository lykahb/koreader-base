-- load common SDL input/video library
local SDL = require("ffi/SDL2_0")
local BB = require("ffi/blitbuffer")
local util = require("ffi/util")
local ffi = require("ffi")
local framebuffer = {
    -- this blitbuffer will be used when we use refresh emulation
    sdl_bb = nil,
}

function framebuffer:init()
    if not self.dummy then
        SDL.open(self.w, self.h, self.x, self.y)
        self:_newBB()
    else
        self.bb = BB.new(600, 800)
    end
    if os.getenv("EMULATE_BW_SCREEN") then
        self.device.hasColorScreen = function() return false end
        self.isColorEnabled = function() return false end
    end

    self.bb:fill(BB.COLOR_WHITE)
    self:refreshFull()

    framebuffer.parent.init(self)
end

function framebuffer:resize(w, h)
    w = w or SDL.w
    h = h or SDL.h

    if not self.dummy then
        self:_newBB(w, h)
        SDL.w = w
        SDL.h = h
    else
        self.bb:free()
        self.bb = BB.new(600, 800)
    end

    if SDL.texture then SDL.destroyTexture(SDL.texture) end
    SDL.texture = SDL.createTexture(w, h)

    self.bb:fill(BB.COLOR_WHITE)
    self:refreshFull()
end

local bb_emu = os.getenv("EMULATE_BB_TYPE")
function framebuffer:_newBB(w, h)
    w = w or SDL.w
    h = h or SDL.h

    local rotation
    local inverse

    if self.sdl_bb then self.sdl_bb:free() end
    if self.bb then
        rotation = self.bb:getRotation()
        inverse = self.bb:getInverse() == 1
        self.bb:free()
    end

    -- we present this buffer to the outside
    local sdl_bb_type = BB["TYPE_" .. (bb_emu or "BBRGB32")]
    local bb = BB.new(w, h, sdl_bb_type)
    local flash = os.getenv("EMULATE_READER_FLASH")
    if flash then
        -- in refresh emulation mode, we use a shadow blitbuffer
        -- and blit refresh areas from it.
        self.sdl_bb = bb
        self.bb = BB.new(w, h, bb:getType())
    else
        self.bb = bb
    end

    if rotation then
        self.bb:setRotation(rotation)
    end

    -- reinit inverse mode on resize
    if inverse then
        self.bb:invert()
    end
end

function framebuffer:_render(bb, x, y, w, h)
    w, x = BB.checkBounds(w or bb:getWidth(), x or 0, 0, bb:getWidth(), 0xFFFF)
    h, y = BB.checkBounds(h or bb:getHeight(), y or 0, 0, bb:getHeight(), 0xFFFF)

    -- x, y, w, h without rotation for SDL rectangle
    local px, py, pw, ph = bb:getPhysicalRect(x, y, w, h)

    -- A viewport is a Blitbuffer object that works on a rectangular
    -- subset of the underlying memory without allocating new memory.
    local bb_rect = bb:viewport(x, y, w, h)
    local sdl_rect = SDL.rect(px, py, pw, ph)

    if not bb_emu then
        SDL.SDL.SDL_UpdateTexture(SDL.texture, sdl_rect, bb_rect.data, bb_rect.stride)
    else
        -- The manual conversion is here deliberately, so as to separate us from possible bugs in the blitter.
        local vbuf = ffi.new("ColorRGB32[?]", pw*ph)
        local pos = 0
        for vy=0, ph-1 do
            for vx=0, pw-1 do
                vbuf[pos] = bb_rect:getPixelP(vx, vy)[0]:getColorRGB32()
                pos = pos+1
            end
        end
        SDL.SDL.SDL_UpdateTexture(SDL.texture, sdl_rect, vbuf, pw * 4)
    end

    SDL.SDL.SDL_RenderClear(SDL.renderer)
    SDL.SDL.SDL_RenderCopy(SDL.renderer, SDL.texture, nil, nil)
    SDL.SDL.SDL_RenderPresent(SDL.renderer)
end

function framebuffer:refreshFullImp(x, y, w, h)
    if self.dummy then return end

    local bb = self.full_bb or self.bb

    if not (x and y and w and h) then
        x = 0
        y = 0
        w = bb:getWidth()
        h = bb:getHeight()
    end

    self.debug("refresh on physical rectangle", x, y, w, h)

    local flash = os.getenv("EMULATE_READER_FLASH")
    if flash then
        self.sdl_bb:invertRect(x, y, w, h)
        self:_render(self.sdl_bb, x, y, w, h)
        util.usleep(tonumber(flash)*1000)
        self.sdl_bb:setRotation(bb:getRotation())
        self.sdl_bb:setInverse(bb:getInverse())
        self.sdl_bb:blitFrom(bb, x, y, x, y, w, h)
    end
    self:_render(bb, x, y, w, h)
end

function framebuffer:setWindowTitle(new_title)
    framebuffer.parent.setWindowTitle(self, new_title)
    SDL.SDL.SDL_SetWindowTitle(SDL.screen, self.window_title)
end

function framebuffer:setWindowIcon(icon)
    SDL.setWindowIcon(icon)
end

function framebuffer:close()
    SDL.SDL.SDL_Quit()
end

return require("ffi/framebuffer"):extend(framebuffer)
