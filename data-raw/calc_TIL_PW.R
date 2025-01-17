############# 1. Calculate TCGA Pathway score through ssGSEA mthod ################

library(IOBR)
library(UCSCXenaShiny)
library(tidyverse)

### toil TCGA 表达信息
# https://toil.xenahubs.net/download/tcga_RSEM_gene_tpm.gz
exp_dat = data.table::fread("tcga_RSEM_gene_tpm.gz")
exp_dat = as.data.frame(exp_dat)
# https://toil.xenahubs.net/download/probeMap/gencode.v23.annotation.gene.probemap
id_map = data.table::fread("gencode.v23.annotation.gene.probemap")
table(exp_dat$sample %in% id_map$id)
exp_dat2 = exp_dat %>% dplyr::mutate(gene=id_map$gene[match(exp_dat$sample,id_map$id)], .before=1)
exp_mat = as.matrix(exp_dat2[,c(-1,-2)])
rownames(exp_mat) = exp_dat2$gene
dim(exp_mat)
# [1] 60498 10535

exp_mat = exp_mat[,colnames(exp_mat) %in% tcga_gtex$sample]
dim(exp_mat)
# [1] 60498 10534
exp_meta = tcga_gtex[match(colnames(exp_mat),tcga_gtex$sample),]
exp_meta = dplyr::mutate(exp_meta, across(where(is.factor), as.character))

# dim(exp_mat)
# exp_mat[1:4,1:4]
# meta_dat = tcga_gtex %>%
#     dplyr::filter(sample %in% colnames(exp_mat)) %>% 
#     # dplyr::filter(type2 == "tumor") %>%
#     dplyr::select(sample, tissue) %>%
#     dplyr::mutate(across(where(is.factor), as.character))
# exp_mat = exp_mat[,meta_dat$sample]
# [1] 60498  9807


### 500个通路基因集信息
signature_collections2 = signature_collection
names(signature_collections2) = paste0("IOBR_",names(signature_collections2))
merge.list = c(hallmark, kegg, signature_collections2)
length(merge.list) #500

summary(map_int(merge.list, length))


### 每个cancer跑一遍ssGSEA流程
walk(sort(unique(exp_meta$tissue)), function(x){
    print(x)
    exp_mat_sle = exp_mat[,exp_meta$sample[exp_meta$tissue==x]]
    sig_score <- GSVA::gsva(exp_mat_sle,
                            merge.list,
                            method="ssgsea",
                            kcdf="Gaussian",
                            parallel.sz = 20)
    save(sig_score, file=paste0("out/",x,".rda"))
})


### 汇总结果，保存为rda文件
toil_sig_score = lapply(sort(unique(exp_meta$tissue)), function(x){
    sig_score = get(load(paste0("out/",x,".rda")))
    sig_score
}) %>% do.call(cbind, .) %>% t()


tcga_PW = toil_sig_score
dim(tcga_PW)
# [1] 10534   500
save(tcga_PW, file="tcga_PW.rda")



sig_meta = data.frame(sig_name=names(merge.list)) %>%
    dplyr::mutate(sig_type=str_split(sig_name,"_",simplify=T)[,1])  %>%
    dplyr::mutate(sig_name2=str_match(sig_name,'^.*?_(.*)$')[,2]) 
sig_meta$sig_origin = sapply(names(merge.list), function(sig_name){
    if(grepl('IOBR',sig_name)){
        sig_name = gsub('IOBR_','',sig_name)
        sig_link = signature_collection_citation$DOI[signature_collection_citation$Signatures==sig_name]
        sig_link = paste0("IOBR package or DOI: ",sig_link)
    } else {
        sig_link = paste0("https://www.gsea-msigdb.org/gsea/msigdb/human/geneset/",sig_name,".html")
    }
    return(sig_link)
})

sig_meta$sig_gene = map_chr(merge.list, function(x){paste(x, collapse="/")})

colnames(sig_meta) = c("ID","Type","Name","Origin","Gene")
tcga_PW_meta = sig_meta
save(tcga_PW_meta, file="tcga_PW_meta.rda")






# sig_score = list(score=toil_sig_score, meta=sig_meta)

# save(sig_score, file="toil_sig_score.rda")






############# 2. Calculate PCAWG Pathway score through ssGSEA mthod ################
library(UCSCXenaShiny)
library(IOBR)
library(tidyverse)

exp_dat = data.table::fread("tophat_star_fpkm_uq.v2_aliquot_gl.sp.log")
exp_dat = as.data.frame(exp_dat)
id_map = data.table::fread("gencode.v19.annotation.gene.probemap")
colnames(id_map)[1] = "id"


exp_dat2 = exp_dat %>% dplyr::mutate(gene=id_map$gene[match(exp_dat$feature,id_map$id)], .before=1)
exp_mat = as.matrix(exp_dat2[,c(-1,-2)])
rownames(exp_mat) = exp_dat2$gene
dim(exp_mat)
# [1] 57820  1521

exp_mat = exp_mat[,colnames(exp_mat) %in% pcawg_info$icgc_specimen_id]
dim(exp_mat)
# [1] 57820  1466

exp_meta = pcawg_info[match(colnames(exp_mat),pcawg_info$icgc_specimen_id),]
exp_meta = dplyr::mutate(exp_meta, across(where(is.factor), as.character))


signature_collections2 = signature_collection
names(signature_collections2) = paste0("IOBR_",names(signature_collections2))
merge.list = c(hallmark, kegg, signature_collections2)
length(merge.list) #500

walk(sort(unique(exp_meta$dcc_project_code)), function(x){
    print(x)
    exp_mat_sle = exp_mat[,exp_meta$icgc_specimen_id[exp_meta$dcc_project_code==x]]
    sig_score <- GSVA::gsva(exp_mat_sle,
                            merge.list,
                            method="ssgsea",
                            kcdf="Gaussian",
                            parallel.sz = 20)
    save(sig_score, file=paste0("out2/",x,".rda"))
})


### 汇总结果，保存为rda文件
pcawg_sig_score = lapply(sort(unique(exp_meta$dcc_project_code)), function(x){
    sig_score = get(load(paste0("out2/",x,".rda")))
    sig_score
}) %>% do.call(cbind, .) %>% t()
dim(pcawg_sig_score)
# [1] 1466  500

write.csv(pcawg_sig_score, file="PCAWG_PW.csv")

pcawg_sig_score = read.csv("PCAWG_PW.csv",row.names = 1)

tcga_PW = load_data("tcga_PW")
pcawg_sig_score = pcawg_sig_score[,colnames(tcga_PW)]

pcawg_PW = pcawg_sig_score
dim(pcawg_PW)
# [1] 1466   500
save(pcawg_PW, file="pcawg_PW.rda")






############# 3. Calculate PCAWG immune infilltration score through immunedeconv package ################
library(UCSCXenaShiny)
library(immunedeconv)
library(tidyverse)
library(e1071)
library(parallel)

# https://xenabrowser.net/datapages/?dataset=tophat_star_fpkm_uq.v2_aliquot_gl.sp.log&host=https://pcawg.xenahubs.net

# https://pcawg-hub.s3.us-east-1.amazonaws.com/download/tophat_star_fpkm_uq.v2_aliquot_gl.sp.log
# https://pcawg-hub.s3.us-east-1.amazonaws.com/download/gencode.v19.annotation.gene.probemap


exp_dat = data.table::fread("tophat_star_fpkm_uq.v2_aliquot_gl.sp.log")
exp_dat = exp_dat %>%
    as.data.frame() %>%
    tibble::column_to_rownames("feature") %>%
    as.matrix()
exp_dat = 2^(exp_dat) #去log2

# not change to TPM; just use the fpkm-uq data
# fpkm_to_tpm <- function(fpkm) {
#   exp(log(fpkm) - log(colSums(fpkm)) + log(1e6))
# }
exp_dat = fpkm_to_tpm(exp_dat)

id_map = data.table::fread("gencode.v19.annotation.gene.probemap")
colnames(id_map)[1] = "id"

exp_dat = exp_dat %>% as.data.frame() %>% 
    tibble::rownames_to_column("feature") %>%
    dplyr::mutate(gene=id_map$gene[match(.data$feature,id_map$id)], .before=1)
exp_mat = as.matrix(exp_dat[,c(-1,-2)])
rownames(exp_mat) = exp_dat$gene
dim(exp_mat)
# [1] 57820  1521


# 去除没有meta信息的samples
exp_mat = exp_mat[,colnames(exp_mat) %in% pcawg_info$icgc_specimen_id]
dim(exp_mat)
# [1] 57820  1466

# 去除重复的基因名
exp_mat = exp_mat[!duplicated(rownames(exp_mat)),]
dim(exp_mat)
# [1] 55763  1466
# https://github.com/omnideconv/immunedeconv/issues/146
exp_mat = exp_mat[rownames(exp_mat) %in% rownames(dataset_racle$expr_mat),]

dim(exp_mat)
# [1] 28830  1466


exp_meta = pcawg_info[match(colnames(exp_mat),pcawg_info$icgc_specimen_id),]
exp_meta = dplyr::mutate(exp_meta, across(where(is.factor), as.character))


codes = sort(unique(exp_meta$dcc_project_code))
walk(codes, function(x){
    print(x)
    # x = "BLCA-US"
    exp_mat_sle = exp_mat[,exp_meta$icgc_specimen_id[exp_meta$dcc_project_code==x]]
    write.csv(exp_mat_sle, file=paste0("out3/",x,".csv"))
})


codes_df = data.frame(code = codes)
write.csv(codes_df, file="codes_df.csv")
# 注释每个project与TCGA的关系
#  [1] "acc"  "blca" "brca" "cesc" "chol" "coad" "dlbc" "esca" "gbm"  "hnsc"
# [11] "kich" "kirc" "kirp" "lgg"  "lihc" "luad" "lusc" "meso" "ov"   "paad"
# [21] "pcpg" "prad" "read" "sarc" "skcm" "stad" "tgct" "thca" "thym" "ucec"
# [31] "ucs"  "uvm" 


codes_df_anno = read.csv("codes_df_anno.csv")

for (i in setdiff(seq(nrow(codes_df_anno)),1:26)){
    # i = 1
    code = codes_df_anno$code[i]
    print(paste0("######",i,"-",code))

    indication = codes_df_anno$tcga[i]
    exp_sub = read.csv(paste0("out3/",code,".csv"),row.names=1)

    ## "timer"
    indications = rep(codes_df_anno$tcga[i], ncol(exp_sub))
    score_timer = deconvolute(exp_sub, method="timer", indications = indications)
    score_timer$cell_type = paste0(score_timer$cell_type,"_TIMER")
    ## "cibersort"
    set_cibersort_binary("./CIBERSORT1.04.R")
    set_cibersort_mat("./LM22.txt")
    score_cibersort = deconvolute(exp_sub, method="cibersort")
    score_cibersort$cell_type = paste0(score_cibersort$cell_type,"_CIBERSORT")
    ## "cibersort_abs"
    set_cibersort_binary("./CIBERSORT1.04.R")
    set_cibersort_mat("./LM22.txt")
    score_cibersort_abs = deconvolute(exp_sub, method="cibersort_abs")
    score_cibersort_abs$cell_type = paste0(score_cibersort_abs$cell_type,"_CIBERSORT-ABS")
    ## "quantiseq"
    score_quantiseq = deconvolute(exp_sub, method="quantiseq")
    score_quantiseq$cell_type = paste0(score_quantiseq$cell_type,"_QUANTISEQ")
    ## "mcp_counter" 需要访问github，可能会访问失败
    score_mcp_counter = deconvolute(exp_sub, method="mcp_counter")
    score_mcp_counter$cell_type = paste0(score_mcp_counter$cell_type,"_MCPCOUNTER")
    ## "xcell"
    score_xcell = deconvolute(exp_sub, method="xcell")
    score_xcell$cell_type = paste0(score_xcell$cell_type,"_XCELL")
    ## "epic"
    score_epic = deconvolute(exp_sub, method="epic")
    score_epic$cell_type = paste0(score_epic$cell_type,"_EPIC")

    score_merge = do.call(rbind, list(score_timer,score_cibersort,score_cibersort_abs,
        score_quantiseq,score_mcp_counter,score_xcell,score_epic))
    write.csv(score_merge, file=paste0("out3/",code,"_TIL.csv"),row.names=F)
}


fls = list.files("out3",pattern = "*TIL.csv", full.names = T)


pcawg_til = lapply(seq(fls), function(i){
    # i = 1
    fl_til = read.csv(fls[i],row.names=1)
    fl_til
}) %>% do.call(cbind, .) %>% t()
pcawg_til = pcawg_til %>% 
  as.data.frame() %>% 
  rownames_to_column("cell_type")

# tcga_til = load_data("tcga_TIL")
# identical(colnames(pcawg_til),colnames(tcga_til))
# # [1] TRUE

save(pcawg_til, file = "pcawg_TIL.rda")






############# 4. Compare PCAWG immune infilltration score whether or not TPM transformation ################
# 以PCAWG中BRCA-US项目中的98个TCGA样本比较与tcga-TIL.rda分析结果的相关性



pcawg_TIL = load_data("pcawg_TIL")
tcga_TIL = load_data("tcga_TIL")

# https://dcc.icgc.org/releases/release_28/Summary
df = data.table::fread("../sample.all_projects.tsv.gz")
colnames(df)
df2 = df[,c("project_code","icgc_specimen_id","submitted_specimen_id")]
colnames(df2) = c("project","pcawg","tcga")

# 定位BRCA-US项目的重复样本
df2 = df2 %>% 
  dplyr::filter(grepl("TCGA",tcga)) %>%
  dplyr::mutate(tcga = substr(tcga, 1, 15)) %>% 
  dplyr::distinct() %>% 
  dplyr::filter(pcawg %in% pcawg_TIL$cell_type) %>% 
  dplyr::filter(tcga %in% tcga_TIL$cell_type)

tcga_TIL_reshaped = tcga_TIL %>% 
  reshape2::melt("cell_type") %>% 
  dplyr::rename(tcga_val=value)

pcawg_TIL_reshaped = pcawg_TIL %>% 
  reshape2::melt("cell_type") %>% 
  dplyr::rename(pcawg_val=value)


samples_sle = df2 %>% 
  dplyr::filter(project=="BRCA-US") %>% 
  dplyr::inner_join(tcga_TIL_reshaped, by=c("tcga"="cell_type")) %>% 
  dplyr::inner_join(pcawg_TIL_reshaped, by=c("pcawg"="cell_type", "variable"="variable")) %>% 
  dplyr::mutate(variable = as.character(variable))


# 分析TIL结果的相关性


## 总体的相关性
cor(samples_sle$tcga_val, samples_sle$pcawg_val, method = "pearson")
cor(samples_sle$tcga_val, samples_sle$pcawg_val, method = "spearman")
summary(lm(samples_sle$tcga_val~samples_sle$pcawg_val))$r.squared

samples_sle %>% 
  ggplot(aes(x = tcga_val, y = pcawg_val)) + 
  geom_point() + 
  xlab("tcga-TIL") + ylab("pcawg-TIL") + 
  theme(text = element_text(size = 15))


## 每种细胞类型的单独相关性

r_merge = lapply(unique(samples_sle$variable), function(x){
  tmp = subset(samples_sle, variable==x)
  r1 = cor(tmp$tcga_val, tmp$pcawg_val, method = "pearson")
  r2 = cor(tmp$tcga_val, tmp$pcawg_val, method = "spearman")
  R2 = summary(lm(tmp$tcga_val~tmp$pcawg_val))$r.squared
  return(c(r1, r2,R2))
}) %>% do.call(rbind, .) %>% as.data.frame()
r_merge$celltype = unique(samples_sle$variable)

mean(r_merge$V1, na.rm = T)
sd(r_merge$V1, na.rm = T)

mean(r_merge$V2, na.rm = T)
sd(r_merge$V2, na.rm = T)


r_merge %>% 
  ggplot(aes(x = V1)) + 
  geom_density() + 
  theme_bw() + 
  xlab("R pearson") + 
  theme(text = element_text(size = 15))

r_merge %>% 
  ggplot(aes(x = V2)) + 
  geom_density() + 
  theme_bw() + 
  xlab("R spearman") + 
  theme(text = element_text(size = 15))


## 按照上述方法计算经TPM转换后的相关性情况，并对比
## 结果发现fpkm-uq的结果更好一些