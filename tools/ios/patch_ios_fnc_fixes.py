#!/usr/bin/env python3
"""
tools/ios/patch_ios_fnc_fixes.py
Fight Night Champion runtime & shader fixes:
1. Texture cache: silence zeroed dummy fetch constants and honor gpu_allow_invalid_fetch_constants.
2. Texture cache: invalidate linear k_8 video ring-buffer textures on wrap-around.
3. Command processor: promote valid type 0/1 fetch constants in register file.
4. VFS Runtime::SetupVfs: mount writable HostPathDevice for \\Device\\Cache and \\Device\\Scratch.
5. VFS VirtualFileSystem::OpenFile: allow opening root volume directories ("D:\\", "cache:\\").
6. Kernel NtQueryVolumeInformationFile: return FILE_DEVICE_DISK (0x00000007) for XFileFsDeviceInformation.
7. Kernel IoDismountVolumeByFileHandle: re-register cache: symbolic links after utility dismount.
8. SPIR-V Texture Fetch: extract exp_adjust from word 3 bits 13..18 instead of word 4 (Fix A).
9. Device Properties: enable textureCompressionBC in Properties struct (Fix C).
10. Device Features: enable textureCompressionBC in VkDevice create info (Fix C).
11. Device Properties: override float controls (disable signed zero/inf/nan preserve, enable denorm flush) (Fix B).
12. SPIR-V Features: disable signed_zero_inf_nan_preserve_float32, enable denorm_flush_to_zero_float32 (Fix B).
13. SPIR-V Color Outputs: sanitize pixel shader color outputs oC0..oC3 (replace NaN with 0, clamp to finite) (Fix B).

    python3 tools/ios/patch_ios_fnc_fixes.py            apply
    python3 tools/ios/patch_ios_fnc_fixes.py --status
    python3 tools/ios/patch_ios_fnc_fixes.py --revert
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from patch_engine import run  # noqa: E402

# 1. Texture Cache (src/graphics/pipeline/texture/cache.cpp)
CACHE_ANCHOR = r'''  switch (fetch.type) {
    case xenos::FetchConstantType::kTexture:
      break;
    case xenos::FetchConstantType::kInvalidTexture:
      if (REXCVAR_GET(gpu_allow_invalid_fetch_constants)) {
        break;
      }
      REXGPU_WARN(
          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "
          "has \"invalid\" type! This is incorrect behavior, but you can try "
          "bypassing this by launching Xenia with "
          "--gpu_allow_invalid_fetch_constants=true.",
          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);
      return;
    default:
      REXGPU_WARN(
          "Texture fetch constant ({:08X} {:08X} {:08X} {:08X} {:08X} {:08X}) "
          "is completely invalid!",
          fetch.dword_0, fetch.dword_1, fetch.dword_2, fetch.dword_3, fetch.dword_4, fetch.dword_5);
      return;
  }'''

CACHE_NEW = r'''  // LOCAL PATCH - Fight Night Champion:
  // Only kInvalidTexture (type 0) may be a game texture descriptor whose type bits
  // were left unset. Type 1 is kInvalidVertex and type 3 is kVertex; interpreting
  // either as a texture can sample arbitrary guest memory and produce corrupted art.
  if (fetch.type == xenos::FetchConstantType::kInvalidTexture) {
    if (fetch.dword_1 == 0 || fetch.dword_2 == 0) {
      return;
    }
  } else if (fetch.type != xenos::FetchConstantType::kTexture) {
    return;
  }'''

VIDEO_RING_ANCHOR = r'''      if (key_changed) {
        binding.texture = FindOrCreateTexture(binding.key);
        load_unsigned_data = true;
      }
      binding.texture_signed = nullptr;'''

VIDEO_RING_NEW = r'''      if (key_changed) {
        binding.texture = FindOrCreateTexture(binding.key);
        load_unsigned_data = true;
      }
      // LOCAL PATCH - Fight Night Champion: Invalidate linear k_8 video ring-buffer textures
      // so fresh CPU-decoded YUV frames are always re-uploaded from guest RAM on wrap-around
      if (!fetch.tiled && (xenos::TextureFormat(fetch.format) == xenos::TextureFormat::k_8)) {
        if (!binding.texture) {
          binding.texture = FindOrCreateTexture(binding.key);
        }
        load_unsigned_data = true;
      }
      binding.texture_signed = nullptr;'''

# 2. In-place Fetch Constant Promotion in GPU Command Processor (src/graphics/vulkan/command_processor.cpp)
FETCH_PROMO_ANCHOR = r'''  const RegisterFile& regs = *register_file_;
  (void)index_buffer_info;'''

FETCH_PROMO_NEW = r'''  const RegisterFile& regs = *register_file_;
  (void)index_buffer_info;

  // LOCAL PATCH - Fight Night Champion (Title ID: 45410915):
  // Promote only candidate texture fetch constants (type 0) in-place in the register file.
  // Type 1 is kInvalidVertex and type 3 is kVertex, so neither is safe to reinterpret as texture.
  // This lets shader analysis, samplers, descriptor sets, and the texture cache recognize
  // candidates as kTexture (type 2).
  for (uint32_t i = 0; i < 32; ++i) {
    uint32_t base_reg = XE_GPU_REG_SHADER_CONSTANT_FETCH_00_0 + i * 6;
    uint32_t dword_0 = register_file_->values[base_reg + 0];
    uint32_t dword_1 = register_file_->values[base_reg + 1];
    uint32_t dword_2 = register_file_->values[base_reg + 2];
    if ((dword_0 & 0x3u) == 0 && dword_1 != 0 && dword_2 != 0) {
      register_file_->values[base_reg + 0] = (dword_0 & ~0x3u) | 0x2u;
    }
  }'''

# 3. SetupVfs (src/system/runtime.cpp)
VFS_ANCHOR = r'''  // NOTE: Do NOT register a device for cache: paths
  // Games handle "device not found" gracefully but don't handle actual device
  // errors (like NAME_COLLISION) well. Let cache: fail cleanly.

  return true;'''

VFS_NEW = r'''  // LOCAL PATCH - Fight Night Champion (Title ID: 45410915):
  // Mount writable HostPathDevice for cache:\ and scratch:\ partitions so
  // XMountUtilityDrive and Instant KO Replays do not fail or freeze.
  std::filesystem::path cache_root_dir = cache_root_.empty() ? (game_data_root_ / "cache") : cache_root_;
  std::filesystem::path cache_host_dir = cache_root_dir / "cache_drive";
  std::filesystem::path scratch_host_dir = cache_root_dir / "scratch_drive";
  std::error_code vfs_ec;
  std::filesystem::create_directories(cache_host_dir, vfs_ec);
  std::filesystem::create_directories(scratch_host_dir, vfs_ec);

  auto cache_device = std::make_unique<rex::filesystem::HostPathDevice>(
      "\\Device\\Cache", cache_host_dir, /*read_only=*/false);
  if (cache_device->Initialize()) {
    file_system_->RegisterDevice(std::move(cache_device));
    file_system_->RegisterSymbolicLink("cache:", "\\Device\\Cache");
    file_system_->RegisterSymbolicLink("CACHE:", "\\Device\\Cache");
    file_system_->RegisterSymbolicLink("utl:", "\\Device\\Cache");
    REXSYS_DEBUG("  Mounted {} at \\Device\\Cache (cache:, CACHE:, utl:)", cache_host_dir.string());
  }

  auto scratch_device = std::make_unique<rex::filesystem::HostPathDevice>(
      "\\Device\\Scratch", scratch_host_dir, /*read_only=*/false);
  if (scratch_device->Initialize()) {
    file_system_->RegisterDevice(std::move(scratch_device));
    file_system_->RegisterSymbolicLink("scratch:", "\\Device\\Scratch");
    file_system_->RegisterSymbolicLink("SCRATCH:", "\\Device\\Scratch");
    REXSYS_DEBUG("  Mounted {} at \\Device\\Scratch (scratch:, SCRATCH:)", scratch_host_dir.string());
  }

  return true;'''

# 4. OpenFile (src/filesystem/virtual_file_system.cpp)
OPEN_ANCHOR = r'''  if (entry) {
    if (entry->attributes() & kFileAttributeDirectory && is_non_directory) {
      return X_STATUS_FILE_IS_A_DIRECTORY;
    }'''

OPEN_NEW = r'''  if (entry) {
    // LOCAL PATCH: Allow opening root volume directories ("D:\", "cache:\")
    // even when the guest omits FILE_DIRECTORY_FILE or sets FILE_NON_DIRECTORY_FILE,
    // so volume probe does not fail with 0xC00000BA:
    if (entry->attributes() & kFileAttributeDirectory && is_non_directory && !entry->name().empty()) {
      return X_STATUS_FILE_IS_A_DIRECTORY;
    }'''

# 5. XFileFsDeviceInformation (src/kernel/xboxkrnl/xboxkrnl_io_info.cpp)
DEVINFO_ANCHOR = r'''    case XFileFsDeviceInformation: {
      auto info = info_ptr.as<X_FILE_FS_DEVICE_INFORMATION*>();
      REXKRNL_WARN("Stub XFileFsDeviceInformation!");
      info->device_type = FILE_DEVICE_UNKNOWN;
      info->characteristics = 0;
      out_length = sizeof(X_FILE_FS_DEVICE_INFORMATION);
      break;
    }'''

DEVINFO_NEW = r'''    case XFileFsDeviceInformation: {
      auto info = info_ptr.as<X_FILE_FS_DEVICE_INFORMATION*>();
      // LOCAL PATCH: Return FILE_DEVICE_DISK (0x00000007) for EA Sports volume probe
      info->device_type.set(static_cast<rex::system::X_FILE_DEVICE_TYPE>(0x00000007));
      info->characteristics = 0;
      out_length = sizeof(X_FILE_FS_DEVICE_INFORMATION);
      break;
    }'''

# 6. IoDismountVolumeByFileHandle (src/kernel/xboxkrnl/xboxkrnl_io.cpp)
DISMOUNT_ANCHOR = r'''u32 IoDismountVolumeByFileHandle_entry(u32 handle) {
  REXKRNL_WARN("IoDismountVolumeByFileHandle({:#x}) - stub", (uint32_t)handle);
  return X_STATUS_SUCCESS;
}'''

DISMOUNT_NEW = r'''u32 IoDismountVolumeByFileHandle_entry(u32 handle) {
  REXKRNL_WARN("IoDismountVolumeByFileHandle({:#x}) - stub", (uint32_t)handle);
  // LOCAL PATCH: Re-ensure cache: symbolic links stay active after EA's utility drive format/dismount check
  REX_KERNEL_FS()->RegisterSymbolicLink("cache:", "\\Device\\Cache");
  REX_KERNEL_FS()->RegisterSymbolicLink("CACHE:", "\\Device\\Cache");
  REX_KERNEL_FS()->RegisterSymbolicLink("utl:", "\\Device\\Cache");
  return X_STATUS_SUCCESS;
}'''

# 7. SPIR-V Texture Fetch exp_adjust (src/graphics/pipeline/shader/spirv_translator_fetch.cpp)
EXP_ADJUST_ANCHOR = r'''        // Apply the exponent bias from the bits 13:18 of the fetch constant
        // word 4.
        spv::Id result_exponent_bias = builder_->createBinBuiltinCall(
            type_float_, ext_inst_glsl_std_450_, GLSLstd450Ldexp, const_float_1_,
            builder_->createTriOp(spv::OpBitFieldSExtract, type_int_, fetch_constant_word_4_signed,
                                  builder_->makeUintConstant(13), builder_->makeUintConstant(6)));'''

EXP_ADJUST_NEW = r'''        // LOCAL PATCH - Fight Night Champion Fix A:
        // Extract exp_adjust from bits 13:18 of fetch constant word 3 (not word 4).
        // On Xenos, word 3 bits 13:18 hold exp_adjust, while word 4 bits 12:21 hold lod_bias.
        id_vector_temp_.clear();
        id_vector_temp_.push_back(const_int_0_);
        id_vector_temp_.push_back(
            builder_->makeIntConstant(int((fetch_constant_word_0_index + 3) >> 2)));
        id_vector_temp_.push_back(
            builder_->makeIntConstant(int((fetch_constant_word_0_index + 3) & 3)));
        spv::Id fetch_constant_word_3 = builder_->createLoad(
            builder_->createAccessChain(spv::StorageClassUniform, uniform_fetch_constants_,
                                        id_vector_temp_),
            spv::NoPrecision);
        spv::Id fetch_constant_word_3_signed =
            builder_->createUnaryOp(spv::OpBitcast, type_int_, fetch_constant_word_3);

        spv::Id result_exponent_bias = builder_->createBinBuiltinCall(
            type_float_, ext_inst_glsl_std_450_, GLSLstd450Ldexp, const_float_1_,
            builder_->createTriOp(spv::OpBitFieldSExtract, type_int_, fetch_constant_word_3_signed,
                                  builder_->makeUintConstant(13), builder_->makeUintConstant(6)));'''

# 8. Device Properties: textureCompressionBC (include/rex/ui/vulkan/device.h)
BC_PROP_ANCHOR = r'''    bool fillModeNonSolid = false;
    bool samplerAnisotropy = false;
    bool occlusionQueryPrecise = false;'''

BC_PROP_NEW = r'''    bool fillModeNonSolid = false;
    bool samplerAnisotropy = false;
    bool textureCompressionBC = false;
    bool occlusionQueryPrecise = false;'''

# 9. Device Features: textureCompressionBC (src/ui/vulkan/vulkan_device.cpp)
BC_FEAT_ANCHOR = r'''    XE_UI_VULKAN_FEATURE(fillModeNonSolid)
    XE_UI_VULKAN_FEATURE(samplerAnisotropy)
    XE_UI_VULKAN_FEATURE(occlusionQueryPrecise)'''

BC_FEAT_NEW = r'''    XE_UI_VULKAN_FEATURE(fillModeNonSolid)
    XE_UI_VULKAN_FEATURE(samplerAnisotropy)
    XE_UI_VULKAN_FEATURE(textureCompressionBC)
    XE_UI_VULKAN_FEATURE(occlusionQueryPrecise)'''

# 10. Override float controls (src/ui/vulkan/vulkan_device.cpp)
FLOAT_PROP_ANCHOR = r'''  if (ext_1_2_KHR_shader_float_controls) {
    XE_UI_VULKAN_PROPERTY_2(properties_1_2_KHR_shader_float_controls,
                            shaderSignedZeroInfNanPreserveFloat32);
    XE_UI_VULKAN_PROPERTY_2(properties_1_2_KHR_shader_float_controls,
                            shaderDenormFlushToZeroFloat32);
    XE_UI_VULKAN_PROPERTY_2(properties_1_2_KHR_shader_float_controls, shaderRoundingModeRTEFloat32);
  }'''

FLOAT_PROP_NEW = r'''  if (ext_1_2_KHR_shader_float_controls) {
    // LOCAL PATCH - Fight Night Champion Fix B:
    // Override float controls: disable signed zero/Inf/NaN preservation (flushes NaNs)
    // and force denorm flush to zero for Apple Silicon / MoltenVK compatibility.
    properties_1_2_KHR_shader_float_controls.shaderSignedZeroInfNanPreserveFloat32 = VK_FALSE;
    properties_1_2_KHR_shader_float_controls.shaderDenormFlushToZeroFloat32 = VK_TRUE;
    XE_UI_VULKAN_PROPERTY_2(properties_1_2_KHR_shader_float_controls,
                            shaderSignedZeroInfNanPreserveFloat32);
    XE_UI_VULKAN_PROPERTY_2(properties_1_2_KHR_shader_float_controls,
                            shaderDenormFlushToZeroFloat32);
    XE_UI_VULKAN_PROPERTY_2(properties_1_2_KHR_shader_float_controls, shaderRoundingModeRTEFloat32);
    device->properties_.shaderSignedZeroInfNanPreserveFloat32 = false;
    device->properties_.shaderDenormFlushToZeroFloat32 = true;
  }'''

# 11. SPIR-V Features Float Controls (src/graphics/pipeline/shader/spirv_translator.cpp)
FLOAT_CTRL_ANCHOR = r'''      signed_zero_inf_nan_preserve_float32(
          vulkan_device->properties().shaderSignedZeroInfNanPreserveFloat32),
      denorm_flush_to_zero_float32(vulkan_device->properties().shaderDenormFlushToZeroFloat32),'''

FLOAT_CTRL_NEW = r'''      // LOCAL PATCH - Fight Night Champion Fix B:
      // Do not preserve NaN/Inf (causes bright green specular/sweat/bloom on Apple Silicon).
      // Force denorm flush to zero for Xenos shader parity.
      signed_zero_inf_nan_preserve_float32(false),
      denorm_flush_to_zero_float32(true),'''

# 12. Pixel Shader Color Sanitization (src/graphics/pipeline/shader/spirv_translator.cpp)
COLOR_SANITIZE_ANCHOR = r'''    value_to_store = builder_->createCompositeInsert(
        builder_->createUnaryOp(spv::OpBitcast, type_float_, point_size), value_to_store,
        type_float3_, 0);
  }

  builder_->createStore(value_to_store, target_pointer);
}'''

COLOR_SANITIZE_NEW = r'''    value_to_store = builder_->createCompositeInsert(
        builder_->createUnaryOp(spv::OpBitcast, type_float_, point_size), value_to_store,
        type_float3_, 0);
  }

  // LOCAL PATCH - Fight Night Champion Fix B:
  // Sanitize pixel shader color outputs (oC0..oC3) before storing to the render target.
  // Xbox 360 Xenos flushes NaNs to 0.0 and clamps color exports.
  // Replace NaN with 0.0 and clamp to finite range [-65504.0, 65504.0] across all component counts (1..4).
  if (result.storage_target == InstructionStorageTarget::kColor &&
      target_num_components >= 1 && target_num_components <= 4) {
    spv::Id comp_type = type_float_vectors_[target_num_components - 1];
    spv::Id bool_type = type_bool_vectors_[target_num_components - 1];
    spv::Id zero_val = const_float_vectors_0_[target_num_components - 1];

    spv::Id const_clamp_min, const_clamp_max;
    if (target_num_components == 1) {
      const_clamp_min = builder_->makeFloatConstant(-65504.0f);
      const_clamp_max = builder_->makeFloatConstant(65504.0f);
    } else {
      id_vector_temp_util_.clear();
      id_vector_temp_util_.resize(target_num_components, builder_->makeFloatConstant(-65504.0f));
      const_clamp_min = builder_->makeCompositeConstant(comp_type, id_vector_temp_util_);
      id_vector_temp_util_.clear();
      id_vector_temp_util_.resize(target_num_components, builder_->makeFloatConstant(65504.0f));
      const_clamp_max = builder_->makeCompositeConstant(comp_type, id_vector_temp_util_);
    }

    spv::Id is_nan = builder_->createUnaryOp(spv::OpIsNan, bool_type, value_to_store);
    spv::Id clean_val =
        builder_->createTriOp(spv::OpSelect, comp_type, is_nan, zero_val, value_to_store);
    value_to_store = builder_->createTriBuiltinCall(comp_type, ext_inst_glsl_std_450_, GLSLstd450FClamp,
                                                    clean_val, const_clamp_min, const_clamp_max);
  }

  builder_->createStore(value_to_store, target_pointer);
}'''

BLOCKS = [
    ("src/graphics/pipeline/texture/cache.cpp", "allow fetch constants marked type 0/1 with valid address and size", CACHE_ANCHOR, CACHE_NEW),
    ("src/graphics/pipeline/texture/cache.cpp", "invalidate linear k_8 video ring-buffer textures on wrap-around", VIDEO_RING_ANCHOR, VIDEO_RING_NEW),
    ("src/graphics/vulkan/command_processor.cpp", "promote valid type 0 fetch constants in-place in register file", FETCH_PROMO_ANCHOR, FETCH_PROMO_NEW),
    ("src/system/runtime.cpp", "mount writable cache and scratch HostPathDevices", VFS_ANCHOR, VFS_NEW),
    ("src/filesystem/virtual_file_system.cpp", "allow opening root volume directories", OPEN_ANCHOR, OPEN_NEW),
    ("src/kernel/xboxkrnl/xboxkrnl_io_info.cpp", "return FILE_DEVICE_DISK for XFileFsDeviceInformation", DEVINFO_ANCHOR, DEVINFO_NEW),
    ("src/kernel/xboxkrnl/xboxkrnl_io.cpp", "re-register cache: symlink on dismount", DISMOUNT_ANCHOR, DISMOUNT_NEW),
    ("src/graphics/pipeline/shader/spirv_translator_fetch.cpp", "extract exp_adjust from word 3 bits 13..18 (Fix A)", EXP_ADJUST_ANCHOR, EXP_ADJUST_NEW),
    ("include/rex/ui/vulkan/device.h", "declare textureCompressionBC property (Fix C)", BC_PROP_ANCHOR, BC_PROP_NEW),
    ("src/ui/vulkan/vulkan_device.cpp", "enable textureCompressionBC device feature (Fix C)", BC_FEAT_ANCHOR, BC_FEAT_NEW),
    ("src/ui/vulkan/vulkan_device.cpp", "override float controls properties (Fix B)", FLOAT_PROP_ANCHOR, FLOAT_PROP_NEW),
    ("src/graphics/pipeline/shader/spirv_translator.cpp", "disable signed zero preserve and enable denorm flush (Fix B)", FLOAT_CTRL_ANCHOR, FLOAT_CTRL_NEW),
    ("src/graphics/pipeline/shader/spirv_translator.cpp", "sanitize pixel shader color outputs oC0..oC3 (Fix B)", COLOR_SANITIZE_ANCHOR, COLOR_SANITIZE_NEW),
]

if __name__ == "__main__":
    sys.exit(run("ios_fnc_fixes", BLOCKS))
