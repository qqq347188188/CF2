// CFCheatHook — 穿越火线手游 1.0.590 (222.ipa) 运行时 IL2CPP 作弊补丁
// 依据 111 外挂（透范瞄）的 7 处二进制 patch 语义，在 222 上以运行时 hook 方式复刻。
// 编译：macOS + Theos（make）；需链接 libil2cpp 导出的 C API（运行时 dlsym）。

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <sys/mman.h>
#import <string.h>
#import <stdint.h>

#pragma mark - IL2CPP Runtime API（运行时动态解析）

typedef void            Il2CppDomain;
typedef void            Il2CppAssembly;
typedef void            Il2CppImage;
typedef void            Il2CppClass;
typedef void            MethodInfo;
typedef uintptr_t       Il2CppMethodPointer;

typedef Il2CppDomain*   (*FN_domain_get)(void);
typedef Il2CppAssembly** (*FN_domain_get_assemblies)(Il2CppDomain*, size_t*);
typedef Il2CppImage*    (*FN_assembly_get_image)(Il2CppAssembly*);
typedef Il2CppClass*    (*FN_class_from_name)(Il2CppImage*, const char*, const char*);
typedef MethodInfo*     (*FN_class_get_method_from_name)(Il2CppClass*, const char*, int);

static FN_domain_get                  _domain_get;
static FN_domain_get_assemblies       _domain_get_assemblies;
static FN_assembly_get_image          _assembly_get_image;
static FN_class_from_name             _class_from_name;
static FN_class_get_method_from_name  _get_method_from_name;

// MethodInfo 布局：methodPointer 固定在偏移 0（Unity 2019~2022 一致）
static Il2CppMethodPointer method_pointer(MethodInfo *m) {
    return *(Il2CppMethodPointer *)m;
}

static void resolve_il2cpp(void) {
    void *h = dlopen(NULL, RTLD_NOW);
    _domain_get            = (FN_domain_get)dlsym(h, "il2cpp_domain_get");
    _domain_get_assemblies = (FN_domain_get_assemblies)dlsym(h, "il2cpp_domain_get_assemblies");
    _assembly_get_image    = (FN_assembly_get_image)dlsym(h, "il2cpp_assembly_get_image");
    _class_from_name       = (FN_class_from_name)dlsym(h, "il2cpp_class_from_name");
    _get_method_from_name  = (FN_class_get_method_from_name)dlsym(h, "il2cpp_class_get_method_from_name");
}

// 在所有 assembly 中按 命名空间.类名 查找类
static Il2CppClass *find_class(const char *ns, const char *cls) {
    if (!_domain_get || !_domain_get_assemblies || !_assembly_get_image || !_class_from_name) return NULL;
    Il2CppDomain *domain = _domain_get();
    if (!domain) return NULL;
    size_t count = 0;
    Il2CppAssembly **assemblies = _domain_get_assemblies(domain, &count);
    for (size_t i = 0; i < count; i++) {
        Il2CppImage *image = _assembly_get_image(assemblies[i]);
        Il2CppClass *k = _class_from_name(image, ns, cls);
        if (k) return k;
    }
    return NULL;
}

static MethodInfo *find_method(const char *ns, const char *cls, const char *name) {
    Il2CppClass *k = find_class(ns, cls);
    if (!k) return NULL;
    return _get_method_from_name(k, name, -1);
}

#pragma mark - 机器码写入

// ARM64 指令编码（小端）
static const uint32_t RET        = 0xD65F03C0; // ret
static const uint32_t MOV_W0_0   = 0x52800000; // mov w0, #0
static const uint32_t MOV_W0_1   = 0x52800020; // mov w0, #1
static const uint32_t NOP        = 0xD503201F; // nop

static void write_insn(uintptr_t addr, uint32_t insn) {
    vm_map_t self = mach_task_self();
    vm_address_t page = addr & ~(vm_address_t)0xFFF;
    vm_protect(self, page, 0x1000, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    *(uint32_t *)addr = insn;
    __builtin___clear_cache((char *)addr, (char *)(addr + 4));
    vm_protect(self, page, 0x1000, 0, VM_PROT_READ | VM_PROT_EXECUTE);
}

static void write_insns(uintptr_t addr, const uint32_t *insns, int n) {
    for (int i = 0; i < n; i++) write_insn(addr + i * 4, insns[i]);
}

// 111 patch 1: 函数序言 -> ret
static void apply_func_ret(const char *ns, const char *cls, const char *name, const char *tag) {
    MethodInfo *m = find_method(ns, cls, name);
    if (!m) { NSLog(@"[CFCheat] %@: METHOD NOT FOUND", @(tag)); return; }
    uintptr_t p = method_pointer(m);
    write_insn(p, RET);
    NSLog(@"[CFCheat] %@ patched @0x%lx (ret)", @(tag), (unsigned long)p);
}

// 111 patch 2/6: 函数开头 -> mov w0,#imm; ret
static void apply_return_const(const char *ns, const char *cls, const char *name, uint32_t mov, const char *tag) {
    MethodInfo *m = find_method(ns, cls, name);
    if (!m) { NSLog(@"[CFCheat] %@: METHOD NOT FOUND", @(tag)); return; }
    uintptr_t p = method_pointer(m);
    uint32_t insns[2] = { mov, RET };
    write_insns(p, insns, 2);
    NSLog(@"[CFCheat] %@ patched @0x%lx (return const)", @(tag), (unsigned long)p);
}

// 111 patch 3: CheckRoleItemIDAvailable — 把开头若干指令替换为参数强制
// 原函数入口语义：mov x1,x21; fmov s0,s15; ...（s15 等为传入浮点参数）
// 目标：x1=1, s0=0.0, s2=0.0，然后跳回原函数 +0x2C 处继续
static void apply_checkrole_patch(const char *tag) {
    MethodInfo *m = find_method("WNFrontEndGame", "NavigationControllerUtil", "CheckRoleItemIDAvailable");
    if (!m) { NSLog(@"[CFCheat] %@: METHOD NOT FOUND", @(tag)); return; }
    uintptr_t p = method_pointer(m);
    // mov w1,#1 ; fmov s0,wzr ; nop ; fmov s2,wzr ; b <原入口+0x14>
    // 说明：在 111 中 patch 区为 0x4E0F838~0x4E0F846（15 字节 = 3 条完整指令 + 3 字节），
    // 这里用 4 条 4 字节指令覆盖等长区间，并用分支跳回原函数。
    uint32_t br = 0x14000000 | (((uint32_t)(0x14 / 4)) & 0x03FFFFFF); // b +0x14
    uint32_t insns[4] = {
        0x52800021, // mov w1, #1
        0x1E2703E0, // fmov s0, wzr
        0x1E2703E2, // fmov s2, wzr
        br          // b 原逻辑
    };
    write_insns(p, insns, 4);
    NSLog(@"[CFCheat] %@ patched @0x%lx", @(tag), (unsigned long)p);
}

// 111 patch 4: PufferPluginSetFileStatus 的 fmul s9,s0,s1 -> fmul s9,s1,s1
// 这是一个 inline 中缀修改。做法：扫描函数前 2KB 找到 0x1E210809（fmul s9,s0,s1），
// 替换为 0x1E212929（fmul s9,s1,s1）。
static void apply_puffer_patch(const char *tag) {
    MethodInfo *m = find_method("IIPSMobile", "IIPSMobilePufferInterface", "PufferPluginSetFileStatus");
    if (!m) { NSLog(@"[CFCheat] %@: METHOD NOT FOUND", @(tag)); return; }
    uintptr_t p = method_pointer(m);
    vm_map_t self = mach_task_self();
    vm_address_t page = p & ~(vm_address_t)0xFFF;
    vm_protect(self, page, 0x1000, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    int patched = 0;
    for (uintptr_t a = p; a < p + 0x800 && !patched; a += 4) {
        uint32_t v = *(uint32_t *)a;
        if (v == 0x1E210809) {          // fmul s9, s0, s1（111 原版字节 09 08 21 1e）
            *(uint32_t *)a = 0x1E210829; // fmul s9, s1, s1（111 改后字节 29 08 21 1e）
            __builtin___clear_cache((char *)a, (char *)(a + 4));
            patched = 1;
            NSLog(@"[CFCheat] %@ patched fmul @0x%lx", @(tag), (unsigned long)a);
        }
    }
    vm_protect(self, page, 0x1000, 0, VM_PROT_READ | VM_PROT_EXECUTE);
    if (!patched) NSLog(@"[CFCheat] %@: fmul pattern not found (version drift)", @(tag));
}

#pragma mark - 入口（等待 UnityFramework 加载后应用 patch）

static void apply_all_patches(void) {
    @autoreleasepool {
        resolve_il2cpp();
        if (!_get_method_from_name || !_domain_get) {
            NSLog(@"[CFCheat] IL2CPP API 尚未就绪，0.5s 后重试...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                apply_all_patches();
            });
            return;
        }
        NSLog(@"[CFCheat] IL2CPP API 就绪，开始应用补丁");
        // P1: FindItemInPutOnNewTab -> ret
        apply_func_ret("WNGameBase.WNTradingHouseSystem", "UITradingSystemController",
                       "FindItemInPutOnNewTab", "P1-find-item");
        // P2: GetViewAssetId -> return 0
        apply_return_const("WNFrontEndGame", "PetAssiActivityItemContentController",
                           "GetViewAssetId", MOV_W0_0, "P2-view-asset-0");
        // P3: CheckRoleItemIDAvailable -> 参数强制
        apply_checkrole_patch("P3-check-role");
        // P4: PufferPluginSetFileStatus -> fmul 操作数替换
        apply_puffer_patch("P4-puffer");
        // P5: JoinTeamRoom -> ret
        apply_func_ret("gcloud_voice", "GCloudVoiceEngine",
                       "JoinTeamRoom", "P5-join-team");
        // P6: <>xLuaBaseProxy_GetViewAssetId -> return 1
        apply_return_const("WNGameBase", "WeaponGadgetSkillController",
                           "<>xLuaBaseProxy_GetViewAssetId", MOV_W0_1, "P6-xlua-view-asset-1");
        NSLog(@"[CFCheat] all patches applied.");
    }
}

__attribute__((constructor)) static void cheat_init(void) {
    @autoreleasepool {
        NSLog(@"[CFCheat] hook dylib 已加载，等待 UnityFramework 初始化...");
        // 延迟 2 秒再尝试，确保 UnityFramework 已加载、IL2CPP API 已导出
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            apply_all_patches();
        });
    }
}
