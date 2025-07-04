Shader "Custom/Chapter7_NormalMapTangentSpaceMat"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Diffuse ("Diffuse", Color) = (1,1,1,1)
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Bump Scale", Float) = 1.0
        _Specular ("Specular", Color) = (1,1,1,1)
        _Gloss ("Gloss", Range(8.0,256)) = 20
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" ,"LightMode" = "UniversalForward"}
        LOD 200

        CGPROGRAM
        // Physically based Standard lighting model, and enable shadows on all light types
        #pragma vertex vert
        #pragma fragment frag
        #include "Lighting.cginc"
        #include "UnityCG.cginc"


        struct a2v
        {
            float4 vertex : POSITION;
            float3 normal : NORMAL;
            float4 tangent : TANGENT;
            float2 texcoord : TEXCOORD0;
        };

        struct v2f
        {
            float4 pos : SV_POSITION;
            float4 uv : TEXCOORD0;
            float3 lightDir : TEXCOORD1;
            float3 viewDir : TEXCOORD2;
            // float3 worldNormal : TEXCOORD0;
            // fixed3 worldPos : TEXCOORD1;
        };


        fixed4 _Color;
        sampler2D _MainTex;
        float4 _MainTex_ST;
        sampler2D _BumpMap;
        float4 _BumpMap_ST;
        float _BumpScale;
        fixed4 _Diffuse;
        fixed4 _Specular;
        float _Gloss;

        v2f vert(a2v v)
        {
            v2f o;
            o.pos = UnityObjectToClipPos(v.vertex);
            // o.worldNormal = UnityObjectToWorldNormal(v.normal);
            // o.worldPos = mul(unity_ObjectToWorld, v.vertex);
            o.uv.xy = v.texcoord * _MainTex_ST.xy + _MainTex_ST.zw; // Adjust UVs based on texture scale and offset
            o.uv.zw = v.texcoord * _BumpMap_ST.xy + _BumpMap_ST.zw; // Adjust UVs for normal map
            o.uv = TRANSFORM_TEX(v.texcoord, _MainTex); // Use Unity's macro to handle texture transformations
            TANGENT_SPACE_ROTATION;
            o.lightDir = normalize(UnityWorldSpaceLightDir(v.vertex));
            o.viewDir = normalize(UnityWorldSpaceViewDir(v.vertex));
            return o;
        }

        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            // Albedo comes from a texture tinted by color
            fixed4 c = tex2D (_MainTex, IN.uv_MainTex) * _Color;
            o.Albedo = c.rgb;
            // Metallic and smoothness come from slider variables
            o.Metallic = _Metallic;
            o.Smoothness = _Glossiness;
            o.Alpha = c.a;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
