namespace WhaleChat;

internal static class NativeGlyphTests
{
    internal static void Run(Action<string,bool> check)
    {
        string json="{\"payload\":\""+new string('x',6000)+"\"}";
        using var legacy=PixelCodec.Render(PixelCodec.Encode(json));
        using var native=new Bitmap(384,130);
        using(var g=Graphics.FromImage(native))g.Clear(Color.FromArgb(23,20,43));
        int[] levels=[0,49,106,159]; // Actual game capture, not the Windows GDI font raster.
        for(int y=0;y<130;y++)for(int cell=0;cell<128;cell++)for(int dx=0;dx<2;dx++){
            var c=legacy.GetPixel(cell*2+dx,y);
            native.SetPixel(cell*3+dx,y,Color.FromArgb(levels[c.R/32],levels[c.G/32],levels[c.B/32]));
        }
        check("native 3px glyph pitch preserves max-width packet",PixelCodec.Decode(native)==json);
        check("legacy 2px packet still decodes",PixelCodec.Decode(legacy)==json);
        using(var crop=native.Clone(new Rectangle(0,0,256,130),native.PixelFormat))
            check("old 256px cropped font image is rejected",PixelCodec.Decode(crop)==null);
        native.SetPixel(17,1,Color.White); // Gap after glyph5; never data.
        check("native glyph gap is not sampled",PixelCodec.Decode(native)==json);
        native.SetPixel(16,1,Color.White);
        check("corrupted native glyph is rejected",PixelCodec.Decode(native)==null);
        using var invalid=new Bitmap(385,130);
        check("unsupported glyph dimensions are rejected",PixelCodec.Decode(invalid)==null);
    }
}
