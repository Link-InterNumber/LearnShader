// URP Fast Subsurface Scattering (SSS) Shader
Shader "Custom/FastSSS"
{
    Properties
    {
        _BaseMap ("Base Color", 2D) = "white" {}
        _BaseColor ("Color", Color) = (1, 1, 1, 1)
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _Metallic ("Metallic", Range(0, 1)) = 0.0
        
        // SSS properties
        _ThicknessMap ("Thickness Map", 2D) = "white" {}
        _SSSColor ("Subsurface Color", Color) = (1, 0.3, 0.2, 1)
        _SSSPower ("Subsurface Power", Range(0.1, 8.0)) = 1.0
        _SSSScale ("Subsurface Scale", Range(0.1, 10.0)) = 1.0
    }
    
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 texcoord     : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float3 positionWS   : TEXCOORD1;
                float3 normalWS     : TEXCOORD2;
                float3 viewDirWS    : TEXCOORD3;
            };
            
            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_ThicknessMap);
            SAMPLER(sampler_ThicknessMap);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _ThicknessMap_ST;
                half4 _BaseColor;
                half _Smoothness;
                half _Metallic;
                half4 _SSSColor;
                half _SSSPower;
                half _SSSScale;
            CBUFFER_END
            
            Varyings vert(Attributes input)
            {
                Varyings output;
                
                // Transform to clip space
                VertexPositionInputs posInputs = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = posInputs.positionCS;
                output.positionWS = posInputs.positionWS;
                
                // Transform normal to world space
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = normalInputs.normalWS;
                
                // Calculate view direction
                output.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                
                // Pass UV coordinates
                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                
                return output;
            }
            
            half4 frag(Varyings input) : SV_Target
            {
                // Sample textures
                half4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                half thickness = SAMPLE_TEXTURE2D(_ThicknessMap, sampler_ThicknessMap, input.uv).r;
                
                // Get lighting data
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(input.positionWS));
                
                // Normalize vectors
                half3 normalWS = normalize(input.normalWS);
                half3 viewDirWS = normalize(input.viewDirWS);
                
                // Calculate basic lighting
                half NdotL = saturate(dot(normalWS, mainLight.direction));
                half3 diffuse = baseColor.rgb * mainLight.color * NdotL;
                
                // Calculate subsurface scattering effect
                half backLight = saturate(dot(-normalWS, mainLight.direction));
                half sss = pow(backLight, _SSSPower) * _SSSScale * thickness;
                half3 subsurface = _SSSColor.rgb * mainLight.color * sss;
                
                // Combine lighting
                half3 finalColor = diffuse + subsurface;
                
                // Add additional lights
                #ifdef _ADDITIONAL_LIGHTS
                uint additionalLightsCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < additionalLightsCount; ++lightIndex)
                {
                    Light light = GetAdditionalLight(lightIndex, input.positionWS);
                    half3 lightDir = light.direction;
                    
                    // Additional light diffuse
                    half ndotl = saturate(dot(normalWS, lightDir));
                    half3 addDiffuse = baseColor.rgb * light.color * ndotl;
                    
                    // Additional light SSS
                    half addBackLight = saturate(dot(-normalWS, lightDir));
                    half addSss = pow(addBackLight, _SSSPower) * _SSSScale * thickness;
                    half3 addSubsurface = _SSSColor.rgb * light.color * addSss;
                    
                    finalColor += (addDiffuse + addSubsurface) * light.distanceAttenuation;
                }
                #endif
                
                return half4(finalColor, baseColor.a);
            }
            ENDHLSL
        }
        
        // Shadow casting support
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
    }
    FallBack "Universal Render Pipeline/Lit"
}