// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/Chapter7/Chapter7_NormalMapTangentSpaceMat"
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
    }
    SubShader
    {
        LOD 200

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
                o.pos = UnityObjectToClipPos(v.vertex); // Transform vertex position to clip space
                // o.worldNormal = UnityObjectToWorldNormal(v.normal);
                // o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.uv.xy = v.texcoord.xy * _MainTex_ST.xy + _MainTex_ST.zw; // Adjust UVs based on texture scale and offset
                o.uv.zw = v.texcoord.xy * _BumpMap_ST.xy + _BumpMap_ST.zw; // Adjust UVs for normal map
                // o.uv = TRANSFORM_TEX(v.texcoord, _MainTex); // Use Unity's macro to handle texture transformations
                TANGENT_SPACE_ROTATION;
                o.lightDir = mul(rotation, ObjSpaceLightDir(v.vertex)).xyz;
                o.viewDir = mul(rotation, ObjSpaceViewDir(v.vertex)).xyz;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed3 tangentLightDir = normalize(i.lightDir);
                fixed3 tangentViewDir = normalize(i.viewDir);

                fixed4 packedNormal = tex2D(_BumpMap, i.uv.zw);
                fixed3 tangentNormal = UnpackNormal(packedNormal);
                tangentNormal.xy *= _BumpScale; // Scale the normal map
                tangentNormal.z = sqrt(1.0 - saturate(dot(tangentNormal.xy, tangentNormal.xy))); // Ensure the normal is normalized

                fixed3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Color.rgb; // Sample the texture and apply color
                fixed3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz * albedo;
                fixed3 diffuse = _LightColor0.rgb * albedo * _Diffuse.rgb * max(0, dot(tangentNormal, tangentLightDir));

                fixed3 halfDir = normalize(tangentLightDir + tangentViewDir);
                fixed3 specular = _LightColor0.rgb * _Specular.rgb * pow(max(0, dot(tangentNormal, halfDir)), _Gloss);

                return fixed4(ambient + diffuse + specular, 1.0);
            }

            ENDCG
        }
    }
    FallBack "Specular"
}
