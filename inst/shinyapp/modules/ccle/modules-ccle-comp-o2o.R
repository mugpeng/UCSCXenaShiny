ui.modules_ccle_comp_o2o = function(id) {
	ns = NS(id)
	fluidPage(
		fluidRow(
			# 初始设置
			column(
				3,
				wellPanel(
					style = "height:1100px",
					h2("S1: Preset", align = "center"),

					h4("1. Modify datasets[opt]") %>% 
						helper(type = "markdown", size = "m", fade = TRUE, 
					                   title = "Set molecular profile origin", 
					                   content = "data_origin"),
					mol_origin_UI(ns("mol_origin2comp"), database = "ccle"),

					h4("2. Choose sites"),
					pickerInput(
						ns("choose_cancer"),NULL,
						choices = sort(unique(ccle_info_fine$Site_Primary)),
						multiple = TRUE,
						selected = sort(unique(ccle_info_fine$Site_Primary)),
						options = list(`actions-box` = TRUE)
					),
					br(),

					h4("3. Filter samples[opt]"),
					h5("Exact filter:"),
					filter_samples_UI(ns("filter_samples2comp"), database = "ccle"),
					br(),
					verbatimTextOutput(ns("filter_phe_id_info")),
					br(),

					h4("4. Upload metadata[opt]") %>% 
						helper(type = "markdown", size = "m", fade = TRUE, 
					                   title = "Upload sample info", 
					                   content = "custom_metadata"),
					shinyFeedback::useShinyFeedback(),
					custom_meta_UI(ns("custom_meta2comp")),
					br(),

					h4("5. Add signature[opt]") %>% 
						helper(type = "markdown", size = "m", fade = TRUE, 
					                   title = "Add molecular signature", 
					                   content = "add_signature"),
					add_signature_UI(ns("add_signature2comp"), database = "ccle"),
				)
			),
			# 分组设置
			column(
				4,
				wellPanel(
					style = "height:1100px",
					h2("S2: Get data", align = "center"),
					# 调用分组模块UI
					group_samples_UI(ns("group_samples2comp"),database = "ccle"),

					# 下载待比较数据
					download_feat_UI(ns("download_y_axis"), 
						button_name="Query variable to compare",database = "ccle")
				)
			),	
			# 分析/绘图/下载
			column(
				5,
				wellPanel(
					h2("S3: Analyze", align = "center"),
					style = "height:1100px",

					shinyWidgets::actionBttn(
						ns("step3_plot_box"), "Go/Update BoxViolin",
				        style = "gradient",
				        icon = icon("chart-line"),
				        color = "primary",
				        block = TRUE,
				        size = "sm"
					),
					br(),
					selectInput(ns("comp_method"), "Comparison metohd",choices = c("t-test", "wilcoxon")),
					br(),
					column(3, colourpicker::colourInput(inputId = ns("group_1_color"), "Color (group-1)", "#E69F00")),
					column(3, colourpicker::colourInput(inputId = ns("group_2_color"), "Color (group-2)", "#56B4E9")),
					column(3, numericInput(inputId = ns("point_size"), label = "Point size", value = 3, step = 0.5)),
					column(3, numericInput(inputId = ns("point_alpha"), label = "Point alpha", value = 0.4, step = 0.1, min = 0, max = 1)),
					
					# verbatimTextOutput(ns("tmp123")),

					fluidRow(
						column(10, offset = 1,
							   plotOutput({ns("comp_plot_box")}, height = "500px") 
						)
					),

				    br(),
				    fluidRow(
				    	column(3, downloadButton(ns("save_plot_bt"), "Figure")),
				    	column(3, offset = 0, downloadButton(ns("save_data_raw"), "Raw data(.csv)")),
				    	column(3, offset = 1, downloadButton(ns("save_data_res"), "Analyzed data(.csv)"))
				    ),

				    br(),
				    fluidRow(
				    	column(2, p("Plot Height:")),
				    	column(3, numericInput(ns("save_plot_H"), NULL ,min = 1, max = 20, value = 10, step = 0.5)),
				    	column(2, p("Plot Width:")),
				    	column(3, numericInput(ns("save_plot_W"), NULL, min = 1, max = 20, value = 10, step = 0.5)),
				        column(
				        	2,
					        prettyRadioButtons(
					          inputId = ns("save_plot_F"),
					          label = NULL,
					          choices = c("pdf", "png"),
					          selected = "pdf",
					          inline = TRUE,
					          icon = icon("check"),
					          animation = "jelly",
					          fill = TRUE
					        )
				        )
				    )
				)
			)
		)

	)


}


server.modules_ccle_comp_o2o = function(input, output, session) {
	ns <- session$ns
	# 记录选择癌症
	cancer_choose <- reactiveValues(name = "lung", phe_primary="",
		filter_phe_id=query_tcga_group(database = "ccle", cancer = "lung", return_all = T))
	observe({
		cancer_choose$name = input$choose_cancer
		cancer_choose$phe_primary <- query_tcga_group(database = "ccle",
			cancer = cancer_choose$name, return_all = T)
	})


	# 数据源设置
	opt_pancan = callModule(mol_origin_Server, "mol_origin2comp", database = "ccle")


	# 自定义上传metadata数据
	custom_meta = callModule(custom_meta_Server, "custom_meta2comp", database = "ccle")
	# signature
	sig_dat = callModule(add_signature_Server, "add_signature2comp", database = "ccle")
	custom_meta_sig = reactive({
		if(is.null(custom_meta())){
			return(sig_dat())
		} else {
			if(is.null(sig_dat())){
				return(custom_meta())
			} else {
				custom_meta_sig = dplyr::inner_join(custom_meta(),sig_dat())
				return(custom_meta_sig)
			}
		}
	})

	## 过滤样本
	# exact filter module
	filter_phe_id = callModule(filter_samples_Server, "filter_samples2comp",
					   database = "ccle",
					   cancers=reactive(cancer_choose$name),
					   custom_metadata=reactive(custom_meta_sig()),
					   opt_pancan = reactive(opt_pancan()))
	observe({
		# exact filter
		if(is.null(filter_phe_id())){
			cancer_choose$filter_phe_id = cancer_choose$phe_primary$Sample
		} else {
			cancer_choose$filter_phe_id = filter_phe_id()
		}

		output$filter_phe_id_info = renderPrint({
			cat(paste0("Tip: ", length(cancer_choose$filter_phe_id), " samples are retained"))
		})
	})
	# 设置分组
	group_final = callModule(group_samples_Server, "group_samples2comp",
						   database = "ccle",
						   cancers=reactive(cancer_choose$name),
						   samples=reactive(cancer_choose$filter_phe_id),
						   custom_metadata=reactive(custom_meta_sig()),
						   opt_pancan = reactive(opt_pancan())
						   )

	# 下载待比较数据
	y_axis_data = callModule(download_feat_Server, "download_y_axis", 
						     database = "ccle", 
							 samples=reactive(cancer_choose$filter_phe_id),
							 custom_metadata=reactive(custom_meta_sig()),
						     opt_pancan = reactive(opt_pancan()),
						     check_numeric=TRUE
							 )

	# 合并分析
	# boxviolin逻辑：先绘图，再提取相关性结果
	merge_data_box = eventReactive(input$step3_plot_box, {
		group_data = group_final()[,c(1,3,4)]
		colnames(group_data) = c("Sample","group","phenotype")
		y_axis_data = y_axis_data()
		data = dplyr::inner_join(y_axis_data, group_data) %>%
			dplyr::select(cancer, Sample, value, group, everything())
		data
	})

	# output$tmp123 = renderPrint({head(merge_data_box())})
	# 检查数据
	observe({
		cancer_choose$single_cancer_ok = min(table(merge_data_box()$group))>=3
	})


	comp_plot_box = eventReactive(input$step3_plot_box, {
		shiny::validate(
			need(try(nrow(merge_data_box())>0), 
				"Please inspect whether to set groups or download variable data in S2 or S3 step."),
		)
		merge_data_box = merge_data_box()

		if(!cancer_choose$single_cancer_ok){
			return("No enough samples for comparing, please check your input.")
		} else {
			comp_method = switch(isolate(input$comp_method),
				`t-test` = "parametric", wilcoxon = "nonparametric")
			p = ggbetweenstats(
			  data  = merge_data_box,
			  x     = "group",
			  y     = "value",
			  xlab = cancer_choose$group,
			  ylab = unique(merge_data_box$id),
			  title = unique(merge_data_box$cancer),
			  bf.message = FALSE,
			  type = comp_method,
			  centrality.plotting = FALSE,
			  median.color = 'black',
			  point.args = list(size = isolate(input$point_size), alpha = isolate(input$point_alpha),
			  	position = ggplot2::position_jitterdodge(dodge.width = 0.6), stroke = 0, na.rm = TRUE)
			) + 
			  ggplot2::scale_color_manual(values = c(isolate(input$group_1_color), isolate(input$group_2_color))) +
			  theme(text = element_text(size=18),
			        plot.title = element_text(size=20, hjust = 0.5),
			        plot.subtitle = element_text(size = 12))
			return(p)
		}
	})

	output$comp_plot_box = renderPlot({comp_plot_box()})

	# 3个下载按钮
	output$save_plot_bt = downloadHandler(
		filename = function(){
			paste0("BoxViolin", "_",format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".",input$save_plot_F)
		},
		content = function(file){
			p = comp_plot_box()
			
		    if (input$save_plot_F == "pdf") {
		      pdf(file, width = input$save_plot_W, height = input$save_plot_H)
		      print(p)
		      dev.off()
		    } else if (input$save_plot_F == "png"){
		      png(file, width = input$save_plot_W, height = input$save_plot_H, res = 600, units = "in")
		      print(p)
		      dev.off()
		    }
		}
	)
	output$save_data_raw = downloadHandler(
		filename = function(){
			paste0("Compare_rawdata_",format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".csv")
		},
		content = function(file){
			p_raw = merge_data_box()
			write.csv(p_raw, file, row.names = FALSE)
		}
	)
	output$save_data_res = downloadHandler(
		filename = function(){
			paste0("Compare_result_",format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".csv")
		},
		content = function(file){
			p_comp = extract_stats(comp_plot_box())$subtitle_data
			p_comp = p_comp[-which(colnames(p_comp)=="expression")]
			p_comp$identifier = unique(merge_data_box()$id)
			p_comp$phenotype = unique(merge_data_box()$phenotype)
			p_comp$group_1 = levels(merge_data_box()$group)[1]
			p_comp$group_2 = levels(merge_data_box()$group)[2]

			write.csv(p_comp, file, row.names = FALSE)
		}
	)


}