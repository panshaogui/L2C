-- tlconfig.lua
return {
   include_dir = {
      ".",
      "std",
   },
   -- 核心修复：指定该文件为整个 L2C 宇宙的全局环境声明！
   global_env_def = "l2c.d",
   gen_compat = "off",
   gen_target = "5.3",
}