using System.Drawing.Text;
using System.Drawing.Imaging;
namespace WhaleChat;
internal static class FontAssetTests
{
    internal static void Run(Action<string,bool> check,string root)
    {
        string path=Path.Combine(root,"addon","DaFeiYu","BridgePixelV2.ttf");
        check("row font is bundled",File.Exists(path));
        using var collection=new PrivateFontCollection();collection.AddFontFile(path);
        using var font=new Font(collection.Families[0],2,FontStyle.Regular,GraphicsUnit.Pixel);
        using var bitmap=new Bitmap(16,4,PixelFormat.Format32bppArgb);using var g=Graphics.FromImage(bitmap);
        g.Clear(Color.Black);g.TextRenderingHint=TextRenderingHint.SingleBitPerPixelGridFit;
        using var format=(StringFormat)StringFormat.GenericTypographic.Clone();format.FormatFlags|=StringFormatFlags.NoWrap|StringFormatFlags.NoClip;
        for(int i=0;i<4;i++){using var brush=new SolidBrush(Color.FromArgb(i*32,i*32,i*32));g.DrawString("M",font,brush,new PointF(i*2,0),format);}
        check("font line metrics exactly two pixels",Math.Abs(font.GetHeight(g)-2)<.01);
        check("font glyph calibration centers rasterize exactly in Windows GDI",Enumerable.Range(0,4).All(i=>bitmap.GetPixel(i*2+1,1).R==i*32));
        bitmap.Save(Path.Combine(root,"verification","font-asset-gdi.png"),ImageFormat.Png);
    }
}
