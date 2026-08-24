[Defines]
  PLATFORM_NAME                  = Bc250CoreUnlockPei
  PLATFORM_GUID                  = 8B4B1E50-033F-42A5-B3FB-408948DD3BC6
  PLATFORM_VERSION               = 0.1
  DSC_SPECIFICATION              = 0x0001001B
  OUTPUT_DIRECTORY               = Build/Bc250CoreUnlockPei
  SUPPORTED_ARCHITECTURES        = IA32
  BUILD_TARGETS                  = RELEASE
  SKUID_IDENTIFIER               = DEFAULT
  FLASH_DEFINITION               = Bc250CoreUnlockPeiPkg.fdf

[Packages]
  MdePkg/MdePkg.dec
  Bc250CoreUnlockPkg.dec

[LibraryClasses]
  BaseLib|MdePkg/Library/BaseLib/BaseLib.inf
  BaseMemoryLib|MdePkg/Library/BaseMemoryLib/BaseMemoryLib.inf
  DebugLib|MdePkg/Library/BaseDebugLibNull/BaseDebugLibNull.inf
  PcdLib|MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  HobLib|MdePkg/Library/PeiHobLib/PeiHobLib.inf
  MemoryAllocationLib|MdePkg/Library/PeiMemoryAllocationLib/PeiMemoryAllocationLib.inf
  PeimEntryPoint|MdePkg/Library/PeimEntryPoint/PeimEntryPoint.inf
  PeiServicesLib|MdePkg/Library/PeiServicesLib/PeiServicesLib.inf
  RegisterFilterLib|MdePkg/Library/RegisterFilterLibNull/RegisterFilterLibNull.inf
  StackCheckLib|MdePkg/Library/StackCheckLibNull/StackCheckLibNull.inf
  PeiServicesTablePointerLib|MdePkg/Library/PeiServicesTablePointerLib/PeiServicesTablePointerLib.inf

[Components]
  Bc250CoreUnlockPei/Bc250CoreUnlockPei.inf
