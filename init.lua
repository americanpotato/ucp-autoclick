local AOBScan = core.AOBScan
local intToHex = utils.intToHex
local writeByte = core.writeByte
local readByte = core.readByte
local itob = utils.itob
local calculateCodeSize = core.calculateCodeSize
local allocateCode = core.allocateCode
local writeCode = core.writeCode
local getRelativeAddress = core.getRelativeAddress
local relTo = core.relTo
local allocate = core.allocate

return {

    enable = function(self, config)
        local crusaderStart = AOBScan("4D 5A 90 00 03 00 00 00 04 00 00 00 FF FF 00 00 B8 00 00 00 00 00 00 00 40 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 18 01 00 00 0E 1F BA 0E 00 B4 09 CD 21 B8 01 4C CD 21 54 68 69 73 20 70 72 6F 67 72 61 6D 20 63 61 6E 6E 6F 74 20 62 65 20 72 75 6E 20 69 6E 20 44 4F 53")
        
        -- 189 when crusader hd
        -- 100 when crusader extreme
        local gameVersion = readByte(crusaderStart + 288)

        local leftClickAddress = -1
        local shiftAddress = -1
        local hook_point = -1
        local shopOpenAddress = -1

        if gameVersion == 189 then
            log(DEBUG, "Crusader HD Detected")
            -- Stronghold Crusader.exe+B2CBAA
            leftClickAddress = crusaderStart + 11717546
            -- Stronghold Crusader.exe+B224F0
            shiftAddress = crusaderStart + 11674864
            -- Stronghold Crusader.exe+68104
            hook_point = crusaderStart + 426244
            -- Stronghold Crusader.exe+AD31CC 
            shopOpenAddress = crusaderStart + 11350476
        elseif gameVersion == 100 then
            log(DEBUG, "Crusader Extreme Detected")
            -- Stronghold_Crusader_Extreme.exe+B2D02A
            leftClickAddress = crusaderStart + 11718698
            -- Stronghold_Crusader_Extreme.exe+B22970
            shiftAddress = crusaderStart + 11676016
            -- Stronghold_Crusader_Extreme.exe+68324 
            hook_point = crusaderStart + 426788
            -- Stronghold_Crusader_Extreme.exe+267CFC2
            shopOpenAddress = crusaderStart + 40357826
        else 
            log(DEBUG, "Game Version Unknown")
        end

        log(DEBUG, "Left click address: " .. intToHex(leftClickAddress))
        log(DEBUG, "Shift address: " .. intToHex(shiftAddress))
        log(DEBUG, "Hook address: " .. intToHex(hook_point))
        log(DEBUG, "Shop address: " .. intToHex(shopOpenAddress))

        local counterAddress = allocate(1)  -- allocate 1 byte for counter
        local lastShiftValue = allocate(1)  -- byte to store previous shift state (0 or 1)

        writeByte(counterAddress, 0x00)     -- initialize counter to 0

        local code = {
            -- -- Save registers we will use (eax, edx, ecx)
            0x50,               -- push eax

            -- 
            -- start of mouse release logic
            -- 

            -- Load shift state into AL
            0xA0, itob(shiftAddress),            -- mov al, [shiftAddress]

            -- Compare AL with [lastShiftValue]
            0x3A, 0x05, itob(lastShiftValue),    -- cmp al, [lastShiftValue]
            0x74, 0x14,                          -- je skip_reset

            -- Compare [lastShiftValue] == 1
            0x80, 0x3D, itob(lastShiftValue), 0x01, -- cmp byte [lastShiftValue], 1
            0x75, 0x0B,                          -- jne skip_reset

            -- Compare AL == 0
            0x3C, 0x00,                          -- cmp al, 0
            0x75, 0x07,                          -- jne skip_reset

            -- shift just released → set [leftClickAddress] = 0
            0xC6, 0x05, itob(leftClickAddress), 0x00, -- mov byte [leftClickAddress], 0

            -- skip_reset:
            -- Save current shift into [lastShiftValue]
            0xA2, itob(lastShiftValue),         -- mov [lastShiftValue], al

            -- 
            -- end of mouse release logic
            -- 

            -- Check if shop is open (byte)
            0xA0, itob(shopOpenAddress), -- mov al, [shopOpenAddress]
            0x84, 0xC0,               -- test al, al
            0x74, 0x2C,               -- je skip_hook

            -- Check if shift is held (byte)
            0xA0, itob(shiftAddress), -- mov al, [shiftAddress]
            0x84, 0xC0,               -- test al, al
            0x74, 0x23,               -- je skip_hook

            -- Load counter (byte)
            0xA0, itob(counterAddress), -- mov al, [counterAddress]
            0xFE, 0xC0,                 -- inc al
            0xA2, itob(counterAddress), -- mov [counterAddress], al

            -- Compare counter with 6
            0x3C, 0x06,               -- cmp al, 6
            0x7C, 0x13,               -- jl continue_hook

            -- Reset counter to 0
            0x30, 0xC0,               -- xor al, al
            0xA2, itob(counterAddress), -- mov [counterAddress], al

            -- Toggle leftClickAddress byte (0 <-> 1)
            -- 1 means mouse down, 0 means mouse up
            0xA0, itob(leftClickAddress), -- mov al, [leftClickAddress]
            0x34, 0x01,                   -- xor al, 1
            0xA2, itob(leftClickAddress), -- mov [leftClickAddress], al

            -- Restore registers
            0x58,               -- pop eax

            -- Original overwritten instructions at hook_point
            0x55,               -- push ebp
            0x56,               -- push esi
            0x57,               -- push edi
            0x8B, 0xF1,         -- mov esi, ecx

            -- Jump back to hook_point + 5 (since we replaced 5 bytes)
            0xE9, function(address)
                return itob(getRelativeAddress(address, hook_point + 5, -4))
            end
        }

        -- Calculate code size and allocate memory for the hook code
        local codeSize = calculateCodeSize(code)
        local codeAddr = allocateCode(codeSize)
        writeCode(codeAddr, code)

        -- Overwrite original code with jump to our hook
        local jmpToHook = {
            0xE9, function(address)
                return itob(getRelativeAddress(address, codeAddr, -4))
            end
        }
        writeCode(hook_point, jmpToHook)

    end,

    disable = function(self, config)
        return false, "not implemented"
    end,

}


