#include <PiPei.h>

#include <Library/PeiServicesLib.h>
#include <Ppi/PciCfg2.h>

#define BC250_HOST_BRIDGE_ID 0x13E01022u
#define BC250_CORE_MASK_REG 0x0115A870u
#define BC250_Q3_COMMAND_REG 0x03B10A20u
#define BC250_Q3_RESPONSE_REG 0x03B10A80u
#define BC250_Q3_ARGUMENT_REG 0x03B10A88u
#define BC250_Q3_WRITE_FF_MESSAGE 0x98u
#define BC250_QUEUE_POLL_ATTEMPTS 2500u
#define BC250_FUSE_DISABLE_REG 0x0005D25Cu
#define AMD_NBIO_SMU_PPI_GUID \
    { \
        0xea335e48, 0x7275, 0x4d2b, \
        { 0x82, 0x76, 0x55, 0xba, 0x55, 0x31, 0xd7, 0xd7 } \
    }
typedef struct amd_nbio_smu_ppi AMD_NBIO_SMU_PPI;

typedef EFI_STATUS (EFIAPI *AMD_NBIO_SMN_READ)(
    IN AMD_NBIO_SMU_PPI *This,
    IN UINTN Instance,
    IN UINT32 Address,
    OUT UINT32 *Value
);

typedef EFI_STATUS (EFIAPI *AMD_NBIO_SMN_WRITE)(
    IN AMD_NBIO_SMU_PPI *This,
    IN UINTN Instance,
    IN UINT32 Address,
    IN UINT32 *Value
);

struct amd_nbio_smu_ppi {
    VOID *Reserved00;
    VOID *Reserved04;
    VOID *Reserved08;
    VOID *SmuServiceRequest;
    VOID *Reserved10;
    AMD_NBIO_SMN_READ SmnRead;
    AMD_NBIO_SMN_WRITE SmnWrite;
};

struct pei_backend_context {
    AMD_NBIO_SMU_PPI *smu;
};

static EFI_GUID mAmdNbioSmuPpiGuid = AMD_NBIO_SMU_PPI_GUID;

static INTN pei_read_smn(VOID *context, UINT32 address, UINT32 *value)
{
    struct pei_backend_context *backend_context = context;
    EFI_STATUS status;

    status = backend_context->smu->SmnRead(
        backend_context->smu,
        0,
        address,
        value
    );
    return EFI_ERROR(status) ? -1 : 0;
}

static INTN pei_write_smn(VOID *context, UINT32 address, UINT32 value)
{
    struct pei_backend_context *backend_context = context;
    EFI_STATUS status;
    UINT32 data = value;

    status = backend_context->smu->SmnWrite(
        backend_context->smu,
        0,
        address,
        &data
    );
    return EFI_ERROR(status) ? -1 : 0;
}

static BOOLEAN wait_for_queue(struct pei_backend_context *context)
{
    UINT32 attempt;

    /*
     * No Stall PPI exists on this platform (the GUID is absent from the whole
     * firmware volume), so pacing comes from the SMN read cycles themselves.
     * Each poll is a full SmnRead PPI call; the bounded attempt count caps the
     * wait and every failure path falls back to the stock boot path.
     */
    for (attempt = 0; attempt < BC250_QUEUE_POLL_ATTEMPTS; ++attempt) {
        UINT32 response = 0;

        if (pei_read_smn(context, BC250_Q3_RESPONSE_REG, &response) != 0) {
            return FALSE;
        }
        if (response == 0x01u) {
            return TRUE;
        }
        if (response >= 0xfcu) {
            return FALSE;
        }
    }
    return FALSE;
}

static INTN apply_early_unlock(struct pei_backend_context *context)
{
    UINT32 mask = 0;
    UINT32 fuse_disable = 0;

    if (pei_read_smn(context, BC250_CORE_MASK_REG, &mask) != 0) {
        return -1;
    }
    if ((mask & 0xffu) == 0xffu) {
        return 0;
    }
    if ((mask & 0xffu) != 0x77u) {
        return -1;
    }
    /*
     * Defense in depth: if the factory marked cores disabled via the fuse
     * register, the extra silicon may be genuinely defective. Respect the
     * marking and stay on stock - the unlock is for software-gated boards
     * with healthy silicon, not a repair tool.
     */
    if (pei_read_smn(context, BC250_FUSE_DISABLE_REG, &fuse_disable) != 0) {
        return -1;
    }
    if (fuse_disable != 0u) {
        return -1;
    }
    if (!wait_for_queue(context)) {
        return -1;
    }
    if (pei_write_smn(context, BC250_Q3_RESPONSE_REG, 0) != 0) {
        return -1;
    }
    if (
        pei_write_smn(
            context,
            BC250_Q3_ARGUMENT_REG,
            BC250_CORE_MASK_REG
        ) != 0
    ) {
        return -1;
    }
    if (pei_write_smn(context, BC250_Q3_ARGUMENT_REG + sizeof(UINT32), 0) != 0) {
        return -1;
    }
    if (
        pei_write_smn(
            context,
            BC250_Q3_COMMAND_REG,
            BC250_Q3_WRITE_FF_MESSAGE
        ) != 0
    ) {
        return -1;
    }
    if (!wait_for_queue(context)) {
        return -1;
    }
    if (pei_read_smn(context, BC250_CORE_MASK_REG, &mask) != 0) {
        return -1;
    }
    /*
     * Return values: -1 = failure/no-op target, 0 = already unlocked,
     * 1 = flipped 0x77 -> 0xff and verified. Only "1" justifies a reset.
     */
    return ((mask & 0xffu) == 0xffu) ? 1 : -1;
}
static EFI_STATUS EFIAPI on_amd_nbio_smu_ppi(
    IN EFI_PEI_SERVICES **PeiServices,
    IN EFI_PEI_NOTIFY_DESCRIPTOR *NotifyDescriptor,
    IN VOID *Ppi
)
{
    struct pei_backend_context context = { 0 };
    EFI_PEI_PCI_CFG2_PPI *pci_cfg = 0;
    EFI_STATUS status;
    UINT32 host_bridge_id = 0;

    (void)NotifyDescriptor;

    if (Ppi == 0) {
        return EFI_SUCCESS;
    }
    status = PeiServicesLocatePpi(
        &gEfiPciCfg2PpiGuid,
        0,
        0,
        (VOID **)&pci_cfg
    );
    if (EFI_ERROR(status)) {
        return EFI_SUCCESS;
    }
    if (pci_cfg->Segment != 0) {
        return EFI_SUCCESS;
    }
    status = pci_cfg->Read(
        (CONST EFI_PEI_SERVICES **)PeiServices,
        pci_cfg,
        EfiPeiPciCfgWidthUint32,
        EFI_PEI_PCI_CFG_ADDRESS(0, 0, 0, 0),
        &host_bridge_id
    );
    if (EFI_ERROR(status) || host_bridge_id != BC250_HOST_BRIDGE_ID) {
        return EFI_SUCCESS;
    }

    context.smu = Ppi;
    if (apply_early_unlock(&context) == 1) {
        /*
         * The SMU latches core bring-up before this PEIM runs, so a fresh
         * flip only takes effect after a reset. Presence survives a warm
         * reset, so the automatic reboot lands with all 8 cores; power loss
         * repeats the cycle exactly once. Stock CcxVhAriPei resets the same
         * way when it changes downcore settings.
         */
        PeiServicesResetSystem();
    }
    return EFI_SUCCESS;
}

static EFI_PEI_NOTIFY_DESCRIPTOR mAmdNbioSmuNotify = {
    EFI_PEI_PPI_DESCRIPTOR_NOTIFY_CALLBACK |
    EFI_PEI_PPI_DESCRIPTOR_TERMINATE_LIST,
    &mAmdNbioSmuPpiGuid,
    on_amd_nbio_smu_ppi
};

EFI_STATUS EFIAPI Bc250CoreUnlockPeiEntryPoint(
    IN EFI_PEI_FILE_HANDLE FileHandle,
    IN CONST EFI_PEI_SERVICES **PeiServices
)
{
    (void)FileHandle;
    (void)PeiServices;
    /*
     * CCX is patched to OPN-Auto (it never re-applies downcore), so dispatch
     * ordering versus AmdCcxVhAriPei no longer matters: whenever this runs -
     * before or after CCX - the flip lands before DXE enumerates CPUs. The
     * notify result is ignored; any failure degrades to the stock 6-core boot.
     */
    return PeiServicesNotifyPpi(&mAmdNbioSmuNotify);
}
