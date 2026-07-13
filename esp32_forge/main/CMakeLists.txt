# 把咱们一会儿 L2C 生成的 main.c 注册进官方骨架
idf_component_register(SRCS "main.c"
                       INCLUDE_DIRS "."
                       )
