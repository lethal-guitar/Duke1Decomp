/* Copyright (C) 2023 Nikolai Wuttke-Hohendorf. All rights reserved.
 *
 * This project is based on disassembly of executable files from the game
 * Duke Nukem, Copyright (C) 1991 Apogee Software, Ltd.
 *
 * Some parts of the code are based on or have been adapted from the Cosmore
 * project, Copyright (c) 2020-2022 Scott Smitelli.
 * See LICENSE_Cosmore file at the root of the repository, or refer to
 * https://github.com/smitelli/cosmore/blob/master/LICENSE.
 *
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>
 */

#include <dos.h>
#include <math.h>
#include <stdio.h>


typedef unsigned char byte;
typedef unsigned int word;

typedef byte bool;

enum
{
  false = 0,
  true = 1
};


word* levelMapData;
int cameraPosX;
int cameraPosY;
int globalAnimStep;

int plPosX;
int plPosY;
byte plClimbUpAnimFramesLeft;
bool plIsFalling;
bool plHangingFromCeiling;
byte plAnimFrame;
bool plHasGrapplingHooks;
bool gmCameraAdjustmentNeeded;

byte* animSpritesData;


/* Defined in GFX.ASM */
void BlitSolidTile(word src, word dst);
void BlitMaskedTile_16x16(byte* far src, word x, word y);


/*
  This is screen position 16,16 as an EGA memory address.
  A row of 320 pixels occupies 40 bytes of EGA address space, 8 pixels
  occupy one byte.
  So we advance by 40*16 = 640 bytes to get to Y position 16, and then add 2
  to advance by 16 pixels horizontally.
*/
#define MAP_DRAW_START_ADDRESS 642

/*
  This is screen position 224,160 - the first address past the end of the game
  viewport. The viewport starts at 16,16 and is 13x10 tiles in size, i.e.
  208x160 (208+16 = 224).
*/
#define MAP_DRAW_END_ADDRESS 6428

#define BACKDROP_SRC_START_OFFSET 0x4000


#define SND_CLING_HOOKS 27
#define SND_HIT_HEAD 38


void pascal PlaySound(int num) { }


void pascal UploadTileset(char* filename, word destOffset, int size)
{
  static byte far* unused;
  static byte far* dest;

  register int i;
  FILE* fp = fopen(filename, "rb");

  if (*filename == 0)
  {
    return;
  }

  unused = MK_FP(0xA000, 0);
  dest = MK_FP(0xA000, 0x4000);

  size /= 4;

  /* Skip ProGraphx file format header */
  fgetc(fp);
  fgetc(fp);
  fgetc(fp);

  for (i = 0; i < size; i++)
  {
    /* Skip mask byte - not transparency for EGA-resident tiles */
    fgetc(fp);

    outport(0x3C4, 0x102);
    *(dest + i + destOffset) = fgetc(fp);

    outport(0x3C4, 0x202);
    *(dest + i + destOffset) = fgetc(fp);

    outport(0x3C4, 0x402);
    *(dest + i + destOffset) = fgetc(fp);

    outport(0x3C4, 0x802);
    *(dest + i + destOffset) = fgetc(fp);
  }

  fclose(fp);
}


bool CanPlayerMoveLeft(void)
{
  word* tile;
  word* tileAbove;
  word* tile2;

  tile2 = tile = levelMapData + ((plPosX + cameraPosX - 3) >> 1) + cameraPosY +
    ((plPosY - 16) >> 4) * 128;

  tileAbove = tile - 128;

  if ((plPosY >> 3) & 1)
  {
    tile2 += 128;
  }

  if (*tile > 0x17FF || *tileAbove > 0x17FF || *tile2 > 0x17FF)
  {
    return false;
  }
  else
  {
    return true;
  }
}


bool CanPlayerMoveRight(void)
{
  word* tile;
  word* tileAbove;
  word* tile2;

  tile2 = tile = levelMapData + ((cameraPosX + plPosX) >> 1) + cameraPosY +
    ((plPosY - 16) >> 4) * 128;

  tileAbove = tile - 128;

  if ((plPosY >> 3) & 1)
  {
    tile2 += 128;
  }

  if (*tile > 0x17FF || *tileAbove > 0x17FF || *tile2 > 0x17FF)
  {
    return false;
  }
  else
  {
    return true;
  }
}


bool CanPlayerMoveUp(void)
{
  word* tile1;
  word* tile2;

  tile2 = tile1 = levelMapData + ((plPosX + cameraPosX - 2) >> 1) + cameraPosY +
    (((plPosY - 40) >> 4) * 128);

  if ((plPosX + cameraPosX) & 1)
  {
    tile2 += 1;
  }

  if (
    *tile1 >= 0x2EE0 || *tile2 >= 0x2EE0 ||
    (*tile1 >= 0x1B80 && *tile1 <= 0x1CA0) ||
    (*tile2 >= 0x1B80 && *tile2 <= 0x1CA0))
  {
    if (!plClimbUpAnimFramesLeft && !plIsFalling)
    {
      if (!plHangingFromCeiling)
      {
        plAnimFrame = 0;

        if (plHasGrapplingHooks)
        {
          plHangingFromCeiling = true;
          gmCameraAdjustmentNeeded = true;

          PlaySound(SND_CLING_HOOKS);
        }
        else
        {
          PlaySound(SND_HIT_HEAD);
        }
      }
    }

    return false;
  }
  else
  {
    plHangingFromCeiling = false;

    if (*tile1 > 0x17FF || *tile2 > 0x17FF)
    {
      if (!plHangingFromCeiling)
      {
        PlaySound(SND_HIT_HEAD);
      }

      return false;
    }
    else
    {
      return true;
    }
  }
}


bool IsPlayerInAir(void)
{
  word* tile1;
  word* tile2;

  if (plClimbUpAnimFramesLeft)
  {
    return false;
  }

  tile2 = tile1 = levelMapData + ((plPosX + cameraPosX - 2) >> 1) + cameraPosY +
    ((plPosY >> 4) * 128);

  if ((plPosX + cameraPosX) & 1)
  {
    tile2 += 1;
  }

  if (*tile1 > 0x17FF || *tile2 > 0x17FF)
  {
    return false;
  }
  else
  {
    return true;
  }
}


void DrawMap(void)
{
  /*
    The horizontal camera position is in "half tiles", i.e. 8-pixel blocks.
    Tiles are 16x16, however. The game can display partial tiles at the edges
    of the screen.
    If the position is even, we can simply start rendering at 16,16.
    But if it's odd, we need to show the 2nd half of each tile in the
    left-most column of tiles.  The low-level tile drawing routine can only
    render entire 16x16 blocks though.  The way the game gets around that is
    by drawing 8 pixels further left than in the "even" case, and then
    overdrawing the HUD border on top of the scene to erase the extraneous 8
    pixel column.
  */
  register int dest = MAP_DRAW_START_ADDRESS - (cameraPosX & 1);
  register word tilesDrawn = 0;

  word* mapCell = levelMapData + (cameraPosX >> 1) + cameraPosY;
  word backdropTile = BACKDROP_SRC_START_OFFSET;

  /*
    Enable EGA latch copies (used by BlitSolidTile) by setting the "write mode"
    to "mode 1 - latched write".
  */
  outport(0x3CE, 0x105);

  /*
    Tick the global animation stepper, this is used for tile animation and
    various other things. The variable's unit is EGA source offsets, so to
    advance by one, we add 0x20 (32 bytes) - this is the amount of memory
    occupied by a single 16x16 pixel tile in planar EGA address space.

    There are 4 steps in total, so the variable repeatedly goes through the
    sequence: 0x00, 0x20, 0x40, 0x60.
  */
  globalAnimStep += 0x20;
  if (globalAnimStep == 0x80)
  {
    globalAnimStep = 0;
  }

  /* Draw tiles */
  do
  {
    if (cameraPosX & 1) /* Equivalent to cameraPosX % 2 */
    {
      /*
        When the camera position is "odd", tiles are drawn shifted to the left
        by 8 pixels. We still want to draw the background in its regular
        position though. This is what this code does: If either the current
        tile or the next is background, then we draw the respective background
        tile, but at 8 pixels further *right* than usual, to cancel out the
        offset of -8 pixels applied at the beginning of the function when the
        camera position is odd.
      */
      if (*mapCell == 0 || *(mapCell + 1) == 0) /* Background A */
      {
        BlitSolidTile(backdropTile, dest + 1);
      }
      else if (*mapCell == 0x20 || *(mapCell + 1) == 0x20) /* Background B */
      {
        BlitSolidTile(backdropTile + 0x4100, dest + 1);
      }
    }
    else
    {
      if (*mapCell == 0) /* Background A */
      {
        BlitSolidTile(backdropTile, dest);
      }
      else if (*mapCell == 0x20) /* Background B */
      {
        BlitSolidTile(backdropTile + 0x4100, dest);
      }
    }

    if (*mapCell > 0x20) /* Not background */
    {
      if (*mapCell < 0x5E0) /* Animated tile */
      {
        BlitSolidTile(*mapCell + globalAnimStep, dest);
      }
      else /* Regular tile */
      {
        BlitSolidTile(*mapCell, dest);
      }
    }

    mapCell++;
    dest += 2; /* Advance destination pointer by 16 pixels horizontally (1 byte
               -> 8 pixels) */

    /*
      Draw 14 tiles per row. The viewport is only 13 tiles wide, but when at an
      odd camera position, drawing starts 8 pixels to the left of the viewport.
      To avoid an 8 pixel gap at the right edge of the viewport, we need to
      draw one additional column of tiles.
    */
    if (++tilesDrawn == 14)
    {
      /*
        Advance video memory target address by 96 pixels horizontally, and
        15 pixels vertically (15*40 -> 600, 96/8 -> 12).
        This puts us at the beginning of the next row of tiles within the
        viewport.
      */
      dest += 612;

      /*
        Advance map cell to next row. We've already advanced by 14 from the
        starting position, so adding a further 114 gives us 128 which is the
        width of a level, thus advancing by one tile along the Y axis.
      */
      mapCell += 114;

      tilesDrawn = 0;
    }
    else
    {
      /* Advance to the next backdrop source offset */
      backdropTile += 0x20;
    }
  } while (dest < MAP_DRAW_END_ADDRESS);

  /* Restore EGA state for subsequent sprite drawing operations */
  outport(0x3CE, 5);
}


void LoadSpriteData(char* filename, byte* buffer, int size)
{
  FILE* fp = fopen(filename, "rb");

  /* Skip ProGraphx file format header */
  fgetc(fp);
  fgetc(fp);
  fgetc(fp);

  fread(buffer, size, 1, fp);

  fclose(fp);
}


/* Unit conversions */
#define WORLD_2_SCREEN_X(a) ((a)-cameraPosX)
#define WORLD_2_SCREEN_Y(a) (((a)-cameraPosY) >> 3)


bool pascal IsOffScreen(int x, int y)
{
  if (
    x >= cameraPosX && x < cameraPosX + 29 && cameraPosY - 64 <= y &&
    cameraPosY + 1280 > y)
  {
    return false;
  }

  return true;
}


int IsTouchingPlayer(int x, int y)
{
  register int deltaY = (plPosY >> 4) * 128 + cameraPosY - y + 2;

  if (abs(plPosX + cameraPosX - x) < 2 && deltaY > 16 && deltaY < 384)
  {
    return true;
  }

  return false;
}


int IntersectsSolidTile(int x, int y)
{
  word* tile1;
  word* tile2;

  tile2 = tile1 = levelMapData + (x >> 1) + ((y >> 7) << 7) - 1;

  if (x & 1)
  {
    tile2 += 1;
  }

  if (*tile1 > 0x17FF || *tile2 > 0x17FF)
  {
    return true;
  }
  else
  {
    return false;
  }
}


/*******************************************************************************
 * Actors
 *******************************************************************************/


void pascal DrawRabbitoidSprite(int frame, int x, int y)
{
  word offset;

  if (frame <= 2)
  {
    offset = frame * 320 + 18240;
  }
  else
  {
    offset = (frame - 3) * 320 + 36480;
  }

  if (!IsOffScreen(x, y - 128))
  {
    BlitMaskedTile_16x16(
      animSpritesData + offset, WORLD_2_SCREEN_X(x), WORLD_2_SCREEN_Y(y));
  }

  if (!IsOffScreen(x, y))
  {
    BlitMaskedTile_16x16(
      animSpritesData + offset + 160,
      WORLD_2_SCREEN_X(x),
      WORLD_2_SCREEN_Y(y) + 16);
  }
}


int main(int argc, char** argv)
{
  return 0;
}
