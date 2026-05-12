using System.IO;
using UnityEditor;
using UnityEngine;

public class RainDropNormalMapGenerator : EditorWindow
{
    private const int TextureSize = 256;
    private const string OutputTextureDirectory = "Assets/RainLens/Textures";
    private const string OutputTexturePath = "Assets/RainLens/Textures/RainDropNormalMap.png";

    [MenuItem("Window/Rain Lens/Generate Drop Normal Map")]
    private static void ShowWindow()
    {
        GetWindow<RainDropNormalMapGenerator>("Drop Normal Map");
    }

    private void OnGUI()
    {
        if (GUILayout.Button("Generate", GUILayout.Height(32)))
        {
            GenerateTexture();
        }
    }

    private static void GenerateTexture()
    {
        const float rx = 0.38f;
        const float ry = 0.32f;
        const float trailWidth = 0.12f;
        const float trailLength = 0.55f;
        const float trailStrength = 0.18f;

        var texture = new Texture2D(TextureSize, TextureSize, TextureFormat.RGBA32, false, true);
        float step = 2f / (TextureSize - 1f);

        float Height(float x, float y)
        {
            float bx = x / rx;
            float by = y / ry;
            float bodyHeight = Mathf.Sqrt(Mathf.Max(0f, 1f - bx * bx - by * by));

            float trailHeight = 0f;
            if (y > 0f)
            {
                float xTerm = Mathf.Max(0f, 1f - Mathf.Abs(x) / trailWidth);
                float yTerm = Mathf.Max(0f, 1f - y / trailLength);
                trailHeight = trailStrength * xTerm * yTerm;
            }

            return Mathf.Clamp01(bodyHeight + trailHeight);
        }

        float SmoothStep(float edge0, float edge1, float x)
        {
            float t = Mathf.Clamp01((x - edge0) / (edge1 - edge0));
            return t * t * (3f - 2f * t);
        }

        for (int yIndex = 0; yIndex < TextureSize; yIndex++)
        {
            for (int xIndex = 0; xIndex < TextureSize; xIndex++)
            {
                float x = (xIndex / (TextureSize - 1f)) * 2f - 1f;
                float y = (yIndex / (TextureSize - 1f)) * 2f - 1f;

                float hL = Height(x - step, y);
                float hR = Height(x + step, y);
                float hD = Height(x, y - step);
                float hU = Height(x, y + step);

                float dHx = (hR - hL) / (2f * step);
                float dHy = (hU - hD) / (2f * step);
                Vector3 normal = new Vector3(-dHx, -dHy, 1f).normalized;

                float normalX = normal.x * 0.5f + 0.5f;
                float normalY = normal.y * 0.5f + 0.5f;

                float bodyMask = SmoothStep(0.42f, 0.30f, new Vector2(x / rx, y / ry).magnitude);
                float trailMask =
                    SmoothStep(trailWidth * 1.1f, trailWidth * 0.3f, Mathf.Abs(x)) *
                    SmoothStep(trailLength * 1.05f, 0.0f, y) *
                    SmoothStep(0.0f, 0.08f, y);

                float b = Mathf.Clamp01(bodyMask + trailMask);
                float a = trailMask;

                texture.SetPixel(xIndex, yIndex, new Color(normalX, normalY, b, a));
            }
        }

        texture.Apply(false, false);

        string absoluteDirectory = Path.Combine(Directory.GetCurrentDirectory(), OutputTextureDirectory);
        Directory.CreateDirectory(absoluteDirectory);

        File.WriteAllBytes(OutputTexturePath, texture.EncodeToPNG());
        Object.DestroyImmediate(texture);

        AssetDatabase.ImportAsset(OutputTexturePath, ImportAssetOptions.ForceUpdate);
        var importer = AssetImporter.GetAtPath(OutputTexturePath) as TextureImporter;
        if (importer != null)
        {
            importer.textureType = TextureImporterType.Default;
            importer.textureCompression = TextureImporterCompression.Uncompressed;
            importer.mipmapEnabled = false;
            importer.sRGBTexture = false;
            importer.alphaSource = TextureImporterAlphaSource.FromInput;
            importer.SaveAndReimport();
        }

        AssetDatabase.Refresh();
        Debug.Log($"Generated rain drop normal map: {OutputTexturePath}");
    }
}
