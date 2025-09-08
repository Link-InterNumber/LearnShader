Shader "Custom/SSS_Fast"
{
    Properties
    {
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1,1,1,1)

        [Normal]_NormalMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Range(0,2)) = 1

        _Metallic ("Metallic", Range(0,1)) = 0
        _Smoothness ("Smoothness", Range(0,1)) = 0.5
        _OcclusionMap ("Occlusion", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0,1)) = 1

        _ThicknessMap ("Thickness Map", 2D) = "white" {}
        _ThicknessScale ("Thickness Scale", Range(0,5)) = 1

        _SSSColor ("SSS Color", Color) = (1,0.75,0.6,1)
        _SSSIntensity ("SSS Intensity", Range(0,3)) = 1
        _SSSFalloff ("SSS Falloff", Range(0.01, 5)) = 1
        _LightWrap ("Light Wrap", Range(0,1)) = 0.4
        _TransmissionPower ("Transmission Power", Range(0.1, 8)) = 2

        [Toggle(_RECEIVE_SHADOWS_ON)] _ReceiveShadows ("Receive Shadows", Float) = 1
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Geometry"
            "RenderType"="Opaque"
        }

        LOD 300
        Cull [_Cull]

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // URP feature toggles
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #pragma shader_feature _ _RECEIVE_SHADOWS_ON
            #pragma shader_feature_local _NORMALMAP

            // Includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            // Textures
            TEXTURE2D(_BaseMap);         SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);       SAMPLER(sampler_NormalMap);
            TEXTURE2D(_OcclusionMap);    SAMPLER(sampler_OcclusionMap);
            TEXTURE2D(_ThicknessMap);    SAMPLER(sampler_ThicknessMap);

            // Properties
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;

                float _BumpScale;
                float _Metallic;
                float _Smoothness;
                float _OcclusionStrength;

                float _ThicknessScale;
                float4 _SSSColor;
                float _SSSIntensity;
                float _SSSFalloff;
                float _LightWrap;
                float _TransmissionPower;

                float _ReceiveShadows;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float3 tangentWS  : TEXCOORD2;
                float3 bitangentWS: TEXCOORD3;
                float2 uv         : TEXCOORD4;
                float4 shadowCoord: TEXCOORD5;
                float  fogCoord   : TEXCOORD6;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float3x3 BuildTBN(float3 nWS, float4 tangentOS)
            {
                float3 tWS = TransformObjectToWorldDir(tangentOS.xyz);
                float3 bWS = cross(nWS, tWS) * (tangentOS.w * GetOddNegativeScale());
                return float3x3(tWS, bWS, nWS);
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 nWS = TransformObjectToWorldNormal(IN.normalOS);

                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(OUT.positionWS);
                OUT.normalWS   = nWS;

                float3 tWS = TransformObjectToWorldDir(IN.tangentOS.xyz);
                float3 bWS = cross(nWS, tWS) * (IN.tangentOS.w * GetOddNegativeScale());
                OUT.tangentWS   = tWS;
                OUT.bitangentWS = bWS;

                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                #if defined(_MAIN_LIGHT_SHADOWS)
                    OUT.shadowCoord = TransformWorldToShadowCoord(OUT.positionWS);
                #else
                    OUT.shadowCoord = 0;
                #endif

                OUT.fogCoord = ComputeFogFactor(OUT.positionCS.z);

                return OUT;
            }

            // Simple Blinn-Phong specular for cheap highlight
            float3 SpecularTerm(float3 N, float3 V, float3 L, float smoothness, float3 F0)
            {
                float3 H = normalize(L + V);
                float ndh = saturate(dot(N, H));
                // Map smoothness to exponent
                float specPow = lerp(8.0, 256.0, smoothness);
                float spec    = pow(ndh, specPow);
                // Fresnel Schlick
                float hv = saturate(dot(H, V));
                float3 F = F0 + (1.0 - F0) * pow(1.0 - hv, 5.0);
                return spec * F;
            }

            struct SurfaceData
            {
                float3 albedo;
                float3 normalWS;
                float  occlusion;
                float  metallic;
                float  smoothness;
                float  thickness;
            };

            SurfaceData SampleSurface(Varyings IN)
            {
                SurfaceData s;

                float4 baseSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                s.albedo = (baseSample.rgb * _BaseColor.rgb);

                #if defined(_NORMALMAP)
                    float4 nrmSample = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv);
                    float3 nrmTS = UnpackNormalScale(nrmSample, _BumpScale);
                    float3x3 TBN = float3x3(normalize(IN.tangentWS), normalize(IN.bitangentWS), normalize(IN.normalWS));
                    s.normalWS = normalize(mul(nrmTS, TBN));
                #else
                    s.normalWS = normalize(IN.normalWS);
                #endif

                float ao = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, IN.uv).g;
                s.occlusion = lerp(1.0, ao, _OcclusionStrength);

                s.metallic = _Metallic;
                s.smoothness = _Smoothness;

                float thick = SAMPLE_TEXTURE2D(_ThicknessMap, sampler_ThicknessMap, IN.uv).r;
                s.thickness = thick * _ThicknessScale;

                return s;
            }

            float3 ComputeSSSAndDiffuse(SurfaceData s, float3 V, Light light, float wrap, float tPower, float sssFalloff, float3 sssColor)
            {
                float3 N = s.normalWS;
                float3 L = light.direction;

                float ndl = dot(N, L);

                // Wrap diffuse (cheap SSS-like broadening near terminator)
                float wrapNdl = saturate((ndl + wrap) / (1.0 + wrap));
                float3 diffuse = wrapNdl * s.albedo;

                // Transmission for back lighting
                float back = saturate(-ndl);                    // only when light is behind the surface
                float viewAlign = saturate(1.0 - dot(N, V));    // stronger near silhouette
                float tAmount = pow(back, tPower) * s.thickness;
                float falloff = exp(-s.thickness * sssFalloff); // decay with thickness scale
                float3 transmission = tAmount * viewAlign * falloff * sssColor;

                // Apply light attenuation and color
                float att = light.distanceAttenuation;
                #if defined(_RECEIVE_SHADOWS_ON)
                    att *= light.shadowAttenuation;
                #endif

                return (diffuse + transmission) * light.color * att;
            }

            float4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                SurfaceData s = SampleSurface(IN);

                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

                // Ambient from SH
                float3 ambient = SampleSH(s.normalWS) * s.albedo * s.occlusion;

                // Main light
                Light mainLight;
                #if defined(_MAIN_LIGHT_SHADOWS)
                    mainLight = GetMainLight(IN.shadowCoord);
                #else
                    mainLight = GetMainLight();
                #endif

                float3 color = 0;

                // Diffuse + SSS (wrap + transmission)
                color += ComputeSSSAndDiffuse(
                    s, V, mainLight,
                    _LightWrap, _TransmissionPower, _SSSFalloff, _SSSColor.rgb * _SSSIntensity
                );

                // Additional lights
                #if defined(_ADDITIONAL_LIGHTS)
                    uint count = GetAdditionalLightsCount();
                    for (uint i = 0; i < count; i++)
                    {
                        Light light = GetAdditionalLight(i, IN.positionWS);
                        color += ComputeSSSAndDiffuse(
                            s, V, light,
                            _LightWrap, _TransmissionPower, _SSSFalloff, _SSSColor.rgb * _SSSIntensity
                        );
                    }
                #endif

                // Simple specular
                float3 F0 = lerp(0.04.xxx, s.albedo, s.metallic);
                float3 specCol = 0;

                // Main light specular
                specCol += SpecularTerm(s.normalWS, V, mainLight.direction, s.smoothness, F0) *
                           mainLight.color * mainLight.distanceAttenuation *
                           (#if defined(_RECEIVE_SHADOWS_ON)  mainLight.shadowAttenuation #else 1.0 #endif);

                #if defined(_ADDITIONAL_LIGHTS)
                    uint count2 = GetAdditionalLightsCount();
                    for (uint i = 0; i < count2; i++)
                    {
                        Light light = GetAdditionalLight(i, IN.positionWS);
                        specCol += SpecularTerm(s.normalWS, V, light.direction, s.smoothness, F0) *
                                   light.color * light.distanceAttenuation *
                                   (#if defined(_RECEIVE_SHADOWS_ON)  light.shadowAttenuation #else 1.0 #endif);
                    }
                #endif

                float3 finalColor = ambient + color + specCol;

                // Fog
                finalColor = MixFog(finalColor, IN.fogCoord);

                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }

        // Shadow caster (for receiving proper shadows)
        Pass
        {
            Name "ShadowCaster"
            Tags{ "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        // Depth only (for depth prepass / SSAO etc.)
        Pass
        {
            Name "DepthOnly"
            Tags{ "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        // Meta pass (lightmapping)
        Pass
        {
            Name "Meta"
            Tags{ "LightMode" = "Meta" }

            Cull Off

            HLSLPROGRAM
            #pragma vertex UniversalVertexMeta
            #pragma fragment UniversalFragmentMeta
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MetaInput.hlsl"
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}