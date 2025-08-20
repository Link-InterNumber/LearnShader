Shader "Custom/URP_InvertedHull_Outline"
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
        _OutlineWidth("Outline Width (object units)", Range(0.0, 1.0)) = 0.05
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "Queue" = "Opaque"}

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
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float _OutlineWidth;
            float4 _OutlineColor;

            struct appdataOutline
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                half fogFactor: TEXCOORD1;
            };

            v2f VertOutline(appdataOutline v)
            {
                v2f o;

                float3 posOffset = v.vertex.xyz + v.normal * _OutlineWidth;
                o.pos = TransformObjectToHClip(float4(posOffset, 1.0));

                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);
                o.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                return o;
            }

            float4 FragOutline(v2f i) : SV_Target
            {
                float3 col = MixFog(_OutlineColor, i.fogFactor);
                return float4(col, 1.0);
            }
            ENDHLSL
        }

        // -- -- Base pass : simple textured (unlit) model -- --
        Pass
        {
            Name "BaseColor"
            Tags
            {
                "RenderType" = "Opaque"
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM
            // Physically based Standard lighting model, and enable shadows on all light types
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            // #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

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
                half fogFactor: TEXCOORD4;
            };


            float4 _Color;
            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _BumpMap;
            float4 _BumpMap_ST;
            float _BumpScale;
            float4 _Diffuse;
            float4 _Specular;
            float _Gloss;

            v2f vert(a2v v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.vertex.xyz);

                o.pos = vertexInput.positionCS; // UnityObjectToClipPos(v.vertex); // Transform vertex position to clip space
                o.uv.xy = v.texcoord.xy * _MainTex_ST.xy + _MainTex_ST.zw; // Adjust UVs based on texture scale and offset
                o.uv.zw = v.texcoord.xy * _BumpMap_ST.xy + _BumpMap_ST.zw; // Adjust UVs for normal map

                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz; // mul(unity_ObjectToWorld, v.vertex).xyz;

                float3 worldNormal = normalize(mul(unity_ObjectToWorld, v.normal));
                float3 worldTangent = normalize(mul(unity_ObjectToWorld, v.tangent.xyz));
                float3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w;

                o.TtoW0 = float4(worldTangent.x, worldBinormal.x, worldNormal.x, worldPos.x);
                o.TtoW1 = float4(worldTangent.y, worldBinormal.y, worldNormal.y, worldPos.y);
                o.TtoW2 = float4(worldTangent.z, worldBinormal.z, worldNormal.z, worldPos.z);

                o.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float3 worldPos = float3(i.TtoW0.w, i.TtoW1.w, i.TtoW2.w);
                float3 lightDir = normalize(GetMainLight().direction);
                float3 viewDir = normalize(_WorldSpaceCameraPos - worldPos);

                float3 bump = UnpackNormal(tex2D(_BumpMap, i.uv.zw));
                bump.xy *= _BumpScale; // Scale the normal map
                bump.z = sqrt(1.0 - saturate(dot(bump.xy, bump.xy))); // Ensure the normal is normalized
                bump = normalize(half3(dot(i.TtoW0.xyz, bump), dot(i.TtoW1.xyz, bump), dot(i.TtoW2.xyz, bump)));

                float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Color.rgb; // Sample the texture and apply color
                float3 ambient = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w).xyz * albedo;
                float3 diffuse = _MainLightColor.rgb * albedo * _Diffuse.rgb * max(0, dot(bump, lightDir));

                float3 halfDir = normalize(lightDir + viewDir);
                float3 specular = _MainLightColor.rgb * _Specular.rgb * pow(max(0, dot(bump, halfDir)), _Gloss);
                
#if defined(_ADDITIONAL_LIGHTS)
                
                int pixelLightCount = GetAdditionalLightsCount(); //获取副光源个数，是整数类型
                for(int index = 0; index < pixelLightCount; index++)
                {
                    Light light = GetAdditionalLight(index, worldPos); //获取其它的副光源世界位置
                    float3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
                    diffuse += LightingLambert(attenuatedLightColor, light.direction, bump);
			        specular += LightingSpecular(attenuatedLightColor, light.direction, bump, viewDir, _Specular, _Gloss);
                }
#endif
                float4 col = float4(ambient + diffuse + specular, 1.0);
                
                col.rgb = MixFog(col.rgb, i.fogFactor);
                return col;
            }

            ENDHLSL
        }
    }

    FallBack "Diffuse"
}