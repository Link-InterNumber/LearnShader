Shader "Custom/OutlineURP"
{
    Properties
    {
        _Color ("Color", Color) = (1, 1, 1, 1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Diffuse ("Diffuse", Color) = (1, 1, 1, 1)
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Bump Scale", Float) = 1.0
        _Specular ("Specular", Color) = (1, 1, 1, 1)
        _Gloss ("Gloss", Range(8.0, 256)) = 20

        _OutlineColor("Outline Color", Color) = (0, 0, 0, 1)
        _OutlineWidth("Outline Width (object units)", Float) = 0.05
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry"}

        // -- -- Outline pass : draw backfaces expanded along normal -- --
        Pass
        {
            Name "OUTLINE"
            Cull Front
            // ZWrite On
            // ZTest LEqual
            // Blend Off

            HLSLPROGRAM
            #pragma vertex VertOutline
            #pragma fragment FragOutline
            #include "UnityCG.cginc"

            float _OutlineWidth;
            float4 _OutlineColor;

            struct appdataOutline
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2fOutline
            {
                float4 pos : SV_POSITION;
            };

            v2fOutline VertOutline(appdataOutline v)
            {
                v2fOutline o;
                // 归一化法线，按本地单位偏移（根据需要调大 _OutlineWidth）
                float3 n = normalize(v.normal);
                float3 posOffset = v.vertex.xyz + n * _OutlineWidth;
                o.pos = UnityObjectToClipPos(float4(posOffset, 1.0));
                return o;
            }

            fixed4 FragOutline(v2fOutline i) : SV_Target
            {
                return _OutlineColor;
            }
            ENDHLSL
        }

        // -- -- Base pass : simple textured (unlit) model -- --
        Pass
        {

            Tags
            {
                // "RenderType" = "Opaque",
                "LightMode" = "UniversalForward"
            }

            CGPROGRAM
            // Physically based Standard lighting model, and enable shadows on all light types
            #pragma vertex vert
            #pragma fragment frag
            #include "Lighting.cginc"
            #include "UnityCG.cginc"
            // #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

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
                float4 TtoW0 : TEXCOORD1; // Tangent to World space rotatio
                float4 TtoW1 : TEXCOORD2; // Tangent to World space
                float4 TtoW2 : TEXCOORD3; // Tangent to World space
                // float3 lightDir : TEXCOORD1;
                // float3 viewDir : TEXCOORD2;
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
                o.pos = UnityObjectToClipPos(v.vertex); // Transform vertex position to clip space
                // o.worldNormal = UnityObjectToWorldNormal(v.normal);
                // o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.uv.xy = v.texcoord.xy * _MainTex_ST.xy + _MainTex_ST.zw; // Adjust UVs based on texture scale and offset
                o.uv.zw = v.texcoord.xy * _BumpMap_ST.xy + _BumpMap_ST.zw; // Adjust UVs for normal map
                // o.uv = TRANSFORM_TEX(v.texcoord, _MainTex); // Use Unity's macro to handle texture transformations

                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

                float3 worldNormal = UnityObjectToWorldNormal(v.normal);
                float3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
                float3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w;

                o.TtoW0 = float4(worldTangent.x, worldBinormal.x, worldNormal.x, worldPos.x);
                o.TtoW1 = float4(worldTangent.y, worldBinormal.y, worldNormal.y, worldPos.y);
                o.TtoW2 = float4(worldTangent.z, worldBinormal.z, worldNormal.z, worldPos.z);

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // Light light = GetMainLight();
                float3 worldPos = float3(i.TtoW0.w, i.TtoW1.w, i.TtoW2.w);
                float3 lightDir = normalize(UnityWorldSpaceLightDir(worldPos));
                float3 viewDir = normalize(UnityWorldSpaceViewDir(worldPos));

                float3 bump = UnpackNormal(tex2D(_BumpMap, i.uv.zw));
                bump.xy *= _BumpScale; // Scale the normal map
                bump.z = sqrt(1.0 - saturate(dot(bump.xy, bump.xy))); // Ensure the normal is normalized
                bump = normalize(half3(dot(i.TtoW0.xyz, bump), dot(i.TtoW1.xyz, bump), dot(i.TtoW2.xyz, bump)));

                fixed3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Color.rgb; // Sample the texture and apply color
                fixed3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz * albedo;
                fixed3 diffuse = _LightColor0.rgb * albedo * _Diffuse.rgb * max(0, dot(bump, lightDir));

                fixed3 halfDir = normalize(lightDir + viewDir);
                fixed3 specular = _LightColor0.rgb * _Specular.rgb * pow(max(0, dot(bump, halfDir)), _Gloss);

                return fixed4(ambient + diffuse + specular, 1.0);
            }

            ENDCG
        }
    }

    FallBack "Diffuse"
}