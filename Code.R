#knitr::opts_chunk$set(echo = TRUE)
set.seed(987654321)
library(knitr)
library(kableExtra)
library(dplyr)
library(ggplot2)
library(tidyr)
library(janitor)
library(ggalluvial)
library(xgboost)
library(rBayesianOptimization)
library(Amelia)
library(patchwork)
#install.packages('tidyquant')
library(SHAPforxgboost)
library(tidyquant)
library(tidyverse)
library(caret)
library(PRROC)
#remotes::install_github("AppliedDataSciencePartners/xgboostExplainer")
library(xgboostExplainer)
library(viridis)
library(xlsx)

protocol_fill_color = "grey25"

theme_bluewhite <- function (base_size = 11, base_family = "serif") {
  theme_bw() %+replace% 
    theme(
      text = element_text(family = "serif"),
      panel.grid.major  = element_line(color = "white"),
      panel.background = element_rect(fill = "grey97"),
      panel.border = element_rect(color = "darkred", fill = NA, size = 1), ##05014a
      axis.line = element_line(color = "grey97"),
      axis.ticks = element_line(color = "grey25"),
      axis.title = element_text(size = 10),
      axis.text = element_text(color = "grey25", size = 10),
      legend.title = element_text(size = 10),
      legend.text = element_text(size = 10),
      plot.title = element_text(size = 15, hjust = 0.5),
      strip.background = element_rect(fill = 'black'),
      strip.text = element_text(size = 10, colour = 'white'), # changes the facet wrap text size and color
      panel.grid.minor = element_blank(),
      legend.position = "bottom"
    )
}

rt=read.table('SAI_final.txt',sep = '\t',header = T,row.names = 1)
rt1=rt[,-c(19,21,22,23,24)]


rt=read.table('SAI.txt',sep = '\t',header = T,row.names = 1)
rt=rt[,-c(19)]
gc()
rt=rt1[rownames(rt),]
str(rt)
rt=as.data.frame(rt)
str(rt)
rt$gender=ifelse(rt$gender==1,0,1)




smp_size <- floor(0.8* nrow(rt))

set.seed(49596)
#set.seed(123456)
train_ind <- sample(seq_len(nrow(rt)), size = smp_size)

#rt=rt[,c('Gender','L','PA','SAC')]
train <- rt[train_ind, ]
test <- rt[-train_ind, ]

table(train$SAC)
table(test$SAC)

#rt=na.omit(rt)

library(dplyr)
X_train <- train %>%
  dplyr::select(-c(SAC)) %>% 
  as.matrix()

Y_train <- train %>% 
  dplyr::select(c(SAC)) %>% 
  as.matrix()

X_test <- test %>% 
  dplyr::select(-c(SAC)) %>% 
  as.matrix()

Y_test <- test %>% 
  dplyr::select(c(SAC)) %>% 
  as.matrix()

str(rt)
MultiMLDataSet <- bind_cols(data.frame(Y_train), data.frame(X_train))
#colnames(MultiMLDataSet)[8] ='SES-CD'

######################### ######################### 
######################### ######################### 
######################### Naive Bayes #########################
#library(e1071)   # NOTE: do not put the package at the top - it conflicts with showwaterfall2

Naive_Bayes_Model <- e1071::naiveBayes(as.factor(SAC) ~ ., data = MultiMLDataSet)
Naive_Bayes_Model

NB_Predictions = predict(Naive_Bayes_Model, X_test)

######################### ######################### 
######################### ######################### 
######################### Logistic Model #########################

Logistic_Model <- glm(as.factor(SAC) ~ ., data = na.omit(MultiMLDataSet), family = "binomial")

Logistic_Predictions = predict(Logistic_Model, data.frame(X_test), type = "response")

Logistic_Predictions_bi = ifelse(Logistic_Predictions > 0.5, 1, 0)

######################### ######################### 
######################### ######################### 
######################### Random Forest #########################
#library(randomForest)  # NOTE: do not put the package at the top - it conflicts with showwaterfall2
Random_Forest_Model <- randomForest::randomForest(as.factor(SAC) ~., data = MultiMLDataSet, na.action = na.omit, ntree = 500, importance = TRUE)

RF_Predictions <- predict(Random_Forest_Model, X_test)

######################### ######################### 
######################### ######################### 
######################### adaBoost ######################### 
library(JOUSBoost)
adaBoost_Y_train <- ifelse(Y_train == 0, -1, 1) # adaBoost expects a 0 and 1 prediction
adaBoost_Model <- adaboost(X_train, adaBoost_Y_train, tree_depth = 8, n_rounds = 100, verbose = FALSE, control = NULL)
adaBoost_Predictions <- predict(adaBoost_Model, X_test)
adaBoost_Predictions <- ifelse(adaBoost_Predictions == -1, 0, 1) # convert back to 0 and 1 predictions

######################### ######################### 
######################### ######################### 
######################### Classification Tree ######################### 

library(rpart)
classTree <- rpart(factor(SAC) ~ ., data = MultiMLDataSet, method = "class")
print(classTree)
plotcp(classTree)
summary(classTree)

classTreePredictions <- predict(classTree, data.frame(X_test),type = "class")
#classTreePredictions= classTreePredictions[,2]
#classTreePredictions
######################### ######################### 
######################### ######################### 
######################### XGBoost #########################

dtrain <- xgb.DMatrix(data = X_train, label = Y_train)


cv_folds <- KFold(Y_train, nfolds = 5, stratified = TRUE, seed = 0)

xgb_cv_bayes <- function(eta, max.depth, min_child_weight, subsample) {
  cv <- xgb.cv(
     params = list(
       booster = "gbtree",
       eta = eta,
       max_depth = max.depth,
       min_child_weight = min_child_weight,
       subsample = subsample,
       colsample_bytree = 0.6,
       lambda = 1,
      alpha = 0,
       objective = "binary:logistic",
       eval_metric = "auc"
       ),
     data = dtrain,
     nround = 10,
     folds = cv_folds,
     prediction = TRUE,
     showsd = TRUE,
     early.stop.round = 5,
     maximize = TRUE,
    verbose = 0
     )
   list(
     Score = cv$evaluation_log[, max(test_auc_mean)], Pred = cv$pred
     )
 }
 
 OPT_Res <- BayesianOptimization(
   xgb_cv_bayes,
   bounds = list(
     eta = c(0.01L, 0.05L, 0.1L, 0.3L),
     max.depth = c(6L, 8L, 12L),
   min_child_weight = c(1L, 10L),
    subsample = c(0.5, 0.8, 1)
     ),
   init_grid_dt = NULL,
   init_points = 10,
   n_iter = 10,
   acq = "ucb",
   kappa = 2.576,
   eps = 0.0,
   verbose = TRUE
   )
 
 params <- list(
   "eta" = unname(OPT_Res$Best_Par["eta"]),
   "max_depth" = unname(OPT_Res$Best_Par["max.depth"]),
   "colsample_bytree" = 1,
   "min_child_weight" = unname(OPT_Res$Best_Par["min_child_weight"]),
   "subsample"= unname(OPT_Res$Best_Par["subsample"]),
   "objective"="binary:logistic",
   "gamma" = 1,
   "lambda" = 1,
   "alpha" = 0,
   "max_delta_step" = 0,
   "colsample_bylevel" = 1,
   "eval_metric"= "auc",
   "set.seed" = 176
   )


watchlist <- list("train" = dtrain)
nround = 20   
xgb.model <- xgb.train(params, dtrain, nround, watchlist)

dtest <- xgb.DMatrix(data = X_test)
XGBpredictions <- predict(object = xgb.model, newdata = dtest, type = 'prob')
XGBPredictions_bi <- ifelse(XGBpredictions > 0.5, 1, 0)

results <- cbind(test, XGBpredictions) %>% 
  mutate(
    pred_status = case_when(
      XGBpredictions > 0.50 ~ 1,
      XGBpredictions <= 0.50 ~ 0
    ),
    correct = case_when(
      SAC == pred_status ~ "Correct",
      TRUE ~ "Incorrect"
    ),
    SAC_text = case_when(
      SAC == 1 ~ "Perished",
      SAC == 0 ~ "Survived"
    )
  ) %>% 
  mutate_at(
    vars(SAC, pred_status, correct, SAC_text), funs(factor)
  ) %>% 
  add_count(SAC, pred_status)


######################### ######################### 
######################### ######################### 
######################### Light GBM ######################### 

library(lightgbm)

lgbm_train <- lgb.Dataset(data = X_train, label = Y_train)
lgbm_test <- lgb.Dataset(data = X_test, label = Y_test)

###############

# Optimal parameters from the grid search
params_lightGBM <- list(
  objective = "binary",
  metric = "auc",
  min_sum_hessian_in_leaf = 0,
  feature_fraction = 0.8,
  lambda_l1 = 2,
  lambda_l2 = 0,
  is_unbalance = FALSE
)

lightGBM.model <- lgb.train(
  data = lgbm_train, 
  params = params_lightGBM, 
  learning_rate = 0.1,
  nrounds = 100
)

lightGBM_Predictions <- predict(object = lightGBM.model, data = X_test, rawscore = FALSE)
lightGBM_Predictions_bi <- ifelse(lightGBM_Predictions > 0.5, 1, 0)


###################### Compare ML models #############################
library(caret)
con_NB <- confusionMatrix(NB_Predictions, factor(Y_test))
con_Logistic <- confusionMatrix(factor(Logistic_Predictions_bi), factor(Y_test))
con_RF <- confusionMatrix(RF_Predictions, factor(Y_test))
con_adaBoost <- confusionMatrix(factor(adaBoost_Predictions), factor(Y_test))
con_classTree <- confusionMatrix(classTreePredictions, factor(Y_test))     
con_LGBM <- confusionMatrix(factor(lightGBM_Predictions_bi), factor(Y_test))
con_XGB <- confusionMatrix(factor(XGBPredictions_bi), factor(Y_test))

#######################################################################################################
#######################################################################################################
#######################################################################################################

################## Performance metrics: #####################

############## Naive Bayes Calculations #####################
MCC_NB <- list(
  TP <- con_NB$table[[1]],
  FP <- con_NB$table[[2]],
  FN <- con_NB$table[[3]],
  TN <- con_NB$table[[4]]
) %>%  # # MCC <- ((TP * TN) - (FP * FN)) / sqrt((TP + FP) * (TP+FN) * (TN+FP) * (TN+FN))
  pmap_dbl(., ~ ((..1 * ..4) - (..2 * ..3))/sqrt((..1 + ..2) * (..1 + ..3) * (..4 + ..2) * (..4 + ..3)))

NB_pred_outcome <- cbind(as.numeric(NB_Predictions), as.numeric(Y_test)) %>% 
  data.frame() %>% 
  setNames(c("predictions", "outcome"))

NB_fg <- NB_pred_outcome %>% 
  filter(outcome == 1) %>%
  pull(predictions)

NB_bg <- NB_pred_outcome %>% 
  filter(outcome == 0) %>%
  pull(predictions)

NB_pr <- PRROC::pr.curve(
  scores.class0 = NB_fg, scores.class1 = NB_bg, curve = TRUE)
############## END Naive Bayes Calculations ###################

############## Logistic Calculations #####################
MCC_Logistic <- list(
  TP <- con_Logistic$table[[1]],
  FP <- con_Logistic$table[[2]],
  FN <- con_Logistic$table[[3]],
  TN <- con_Logistic$table[[4]]
) %>%  # # MCC <- ((TP * TN) - (FP * FN)) / sqrt((TP + FP) * (TP+FN) * (TN+FP) * (TN+FN))
  pmap_dbl(., ~ ((..1 * ..4) - (..2 * ..3))/sqrt((..1 + ..2) * (..1 + ..3) * (..4 + ..2) * (..4 + ..3)))

Logistic_pred_outcome <- cbind(as.numeric(Logistic_Predictions), as.numeric(Y_test)) %>% 
  data.frame() %>% 
  setNames(c("predictions", "outcome"))

Logistic_fg <- Logistic_pred_outcome %>% 
  filter(outcome == 1) %>%
  drop_na() %>% 
  pull(predictions)

Logistic_bg <- Logistic_pred_outcome %>% 
  filter(outcome == 0) %>%
  drop_na() %>% 
  pull(predictions)

Logistic_pr <- PRROC::pr.curve(
  scores.class0 = Logistic_fg, scores.class1 = Logistic_bg, curve = TRUE)
############## END Logistic Calculations ###################

############## Random Forest Calculations #####################
MCC_RF <- list(
  TP <- con_RF$table[[1]],
  FP <- con_RF$table[[2]],
  FN <- con_RF$table[[3]],
  TN <- con_RF$table[[4]]
) %>%  # # MCC <- ((TP * TN) - (FP * FN)) / sqrt((TP + FP) * (TP+FN) * (TN+FP) * (TN+FN))
  pmap_dbl(., ~ ((..1 * ..4) - (..2 * ..3))/sqrt((..1 + ..2) * (..1 + ..3) * (..4 + ..2) * (..4 + ..3)))

RF_pred_outcome <- cbind(as.numeric(RF_Predictions), as.numeric(Y_test)) %>% 
  data.frame() %>% 
  setNames(c("predictions", "outcome"))

RF_fg <- RF_pred_outcome %>% 
  filter(outcome == 1) %>%
  drop_na() %>% 
  pull(predictions)

RF_bg <- RF_pred_outcome %>% 
  filter(outcome == 0) %>%
  drop_na() %>% 
  pull(predictions)

RF_pr <- PRROC::pr.curve(
  scores.class0 = RF_fg, scores.class1 = RF_bg, curve = TRUE)
############## END Random Forest Calculations ###################

############## adaBoost Calculations #####################
MCC_adaBoost <- list(
  TP <- con_adaBoost$table[[1]],
  FP <- con_adaBoost$table[[2]],
  FN <- con_adaBoost$table[[3]],
  TN <- con_adaBoost$table[[4]]
) %>%  # # MCC <- ((TP * TN) - (FP * FN)) / sqrt((TP + FP) * (TP+FN) * (TN+FP) * (TN+FN))
  pmap_dbl(., ~ ((..1 * ..4) - (..2 * ..3))/sqrt((..1 + ..2) * (..1 + ..3) * (..4 + ..2) * (..4 + ..3)))

adaBoost_pred_outcome <- cbind(as.numeric(adaBoost_Predictions), as.numeric(Y_test)) %>% 
  data.frame() %>% 
  setNames(c("predictions", "outcome"))

adaBoost_fg <- adaBoost_pred_outcome %>% 
  filter(outcome == 1) %>%
  pull(predictions)

adaBoost_bg <- adaBoost_pred_outcome %>% 
  filter(outcome == 0) %>%
  pull(predictions)

adaBoost_pr <- PRROC::pr.curve(
  scores.class0 = adaBoost_fg, scores.class1 = adaBoost_bg, curve = TRUE)
############## END adaBoost Calculations ###################

############## Class Tree Calculations #####################
MCC_classTree <- list(
  TP <- con_classTree$table[[1]],
  FP <- con_classTree$table[[2]],
  FN <- con_classTree$table[[3]],
  TN <- con_classTree$table[[4]]
) %>%  # # MCC <- ((TP * TN) - (FP * FN)) / sqrt((TP + FP) * (TP+FN) * (TN+FP) * (TN+FN))
  pmap_dbl(., ~ ((..1 * ..4) - (..2 * ..3))/sqrt((..1 + ..2) * (..1 + ..3) * (..4 + ..2) * (..4 + ..3)))

classTree_pred_outcome <- cbind(as.numeric(classTreePredictions), as.numeric(Y_test)) %>% 
  data.frame() %>% 
  setNames(c("predictions", "outcome"))

classTree_fg <- classTree_pred_outcome %>% 
  filter(outcome == 1) %>%
  pull(predictions)

classTree_bg <- classTree_pred_outcome %>% 
  filter(outcome == 0) %>%
  pull(predictions)

classTree_pr <- PRROC::pr.curve(
  scores.class0 = classTree_fg, scores.class1 = classTree_bg, curve = TRUE)
############## END Classification Tree Calculations ###################

############## Light GBM Calculations #####################
MCC_LGBM <- list(
  TP <- con_LGBM$table[[1]],
  FP <- con_LGBM$table[[2]],
  FN <- con_LGBM$table[[3]],
  TN <- con_LGBM$table[[4]]
) %>%  # # MCC <- ((TP * TN) - (FP * FN)) / sqrt((TP + FP) * (TP+FN) * (TN+FP) * (TN+FN))
  pmap_dbl(., ~ ((..1 * ..4) - (..2 * ..3))/sqrt((..1 + ..2) * (..1 + ..3) * (..4 + ..2) * (..4 + ..3)))

LGBM_pred_outcome <- cbind(as.numeric(lightGBM_Predictions), as.numeric(Y_test)) %>% 
  data.frame() %>% 
  setNames(c("predictions", "outcome"))

LGBM_fg <- LGBM_pred_outcome %>% 
  filter(outcome == 1) %>%
  pull(predictions)

LGBM_bg <- LGBM_pred_outcome %>% 
  filter(outcome == 0) %>%
  pull(predictions)

LGBM_pr <- PRROC::pr.curve(
  scores.class0 = LGBM_fg, scores.class1 = LGBM_bg, curve = TRUE)
############## END Light GBM Calculations ###################

#######################################################################################################
#######################################################################################################
#######################################################################################################

############## XGBoost Calculations #####################
MCC_XGB <- list(
  TP <- con_XGB$table[[1]],
  FP <- con_XGB$table[[2]],
  FN <- con_XGB$table[[3]],
  TN <- con_XGB$table[[4]]
) %>%  # # MCC <- ((TP * TN) - (FP * FN)) / sqrt((TP + FP) * (TP+FN) * (TN+FP) * (TN+FN))
  pmap_dbl(., ~ ((..1 * ..4) - (..2 * ..3))/sqrt((..1 + ..2) * (..1 + ..3) * (..4 + ..2) * (..4 + ..3)))

XGB_pred_outcome <- cbind(as.numeric(XGBpredictions), as.numeric(Y_test)) %>% 
  data.frame() %>% 
  setNames(c("predictions", "outcome"))

XGB_fg <- XGB_pred_outcome %>% 
  filter(outcome == 1) %>%
  pull(predictions)

XGB_bg <- XGB_pred_outcome %>% 
  filter(outcome == 0) %>%
  pull(predictions)

XGB_pr <- PRROC::pr.curve(
  scores.class0 = XGB_fg, scores.class1 = XGB_bg, curve = TRUE)
############## END XGBoost Calculations ###################


#######################################################################################################
#######################################################################################################
#######################################################################################################

performanceTable <- data.frame(
  Metric = c("Accuracy", "Sensitivity", "Specificity", "Precision", "F1", "MCC", "AUC", "AUPRC", "TP", "FP", "FN", "TN"),
  `Naive Bayes` = c(
    con_NB$overall["Accuracy"],
    con_NB$byClass["Sensitivity"],
    con_NB$byClass["Specificity"],
    con_NB$byClass["Precision"],
    con_NB$byClass["F1"],
    MCC_NB,
    pROC::auc(as.numeric(Y_test), as.numeric(NB_Predictions)),
    NB_pr$auc.integral,
    con_NB$table[[1]],
    con_NB$table[[2]],
    con_NB$table[[3]],
    con_NB$table[[4]]
  ),
  `Logistic Regression` = c(
    con_Logistic$overall["Accuracy"],
    con_Logistic$byClass["Sensitivity"],
    con_Logistic$byClass["Specificity"],
    con_Logistic$byClass["Precision"],
    con_Logistic$byClass["F1"],
    MCC_Logistic,
    pROC::auc(as.numeric(Y_test), as.numeric(Logistic_Predictions)),
    Logistic_pr$auc.integral,
    con_Logistic$table[[1]],
    con_Logistic$table[[2]],
    con_Logistic$table[[3]],
    con_Logistic$table[[4]]
  ),
  `Classification Tree` = c(
    con_classTree$overall["Accuracy"],
    con_classTree$byClass["Sensitivity"],
    con_classTree$byClass["Specificity"],
    con_classTree$byClass["Precision"],
    con_classTree$byClass["F1"],
    MCC_classTree,
    pROC::auc(as.numeric(Y_test), as.numeric(classTreePredictions)),
    classTree_pr$auc.integral,
    con_classTree$table[[1]],
    con_classTree$table[[2]],
    con_classTree$table[[3]],
    con_classTree$table[[4]]
  ),
  `Random Forest` = c(
    con_RF$overall["Accuracy"],
    con_RF$byClass["Sensitivity"],
    con_RF$byClass["Specificity"],
    con_RF$byClass["Precision"],
    con_RF$byClass["F1"],
    MCC_RF,
    pROC::auc(as.numeric(Y_test), as.numeric(RF_Predictions)),
    RF_pr$auc.integral,
    con_RF$table[[1]],
    con_RF$table[[2]],
    con_RF$table[[3]],
    con_RF$table[[4]]
    
  ),
  `adaBoost` = c(
    con_adaBoost$overall["Accuracy"],
    con_adaBoost$byClass["Sensitivity"],
    con_adaBoost$byClass["Specificity"],
    con_adaBoost$byClass["Precision"],
    con_adaBoost$byClass["F1"],
    MCC_adaBoost,
    pROC::auc(as.numeric(Y_test), as.numeric(adaBoost_Predictions)),
    adaBoost_pr$auc.integral,
    con_adaBoost$table[[1]],
    con_adaBoost$table[[2]],
    con_adaBoost$table[[3]],
    con_adaBoost$table[[4]]
  ),
  `XGBoost` = c(
    con_XGB$overall["Accuracy"],
    con_XGB$byClass["Sensitivity"],
    con_XGB$byClass["Specificity"],
    con_XGB$byClass["Precision"],
    con_XGB$byClass["F1"],
    MCC_XGB,
    pROC::auc(as.numeric(Y_test), as.numeric(XGBpredictions)),
    XGB_pr$auc.integral,
    con_XGB$table[[1]],
    con_XGB$table[[2]],
    con_XGB$table[[3]],
    con_XGB$table[[4]]
  )
,
  `Light GBM` = c(
    con_LGBM$overall["Accuracy"],
    con_LGBM$byClass["Sensitivity"],
    con_LGBM$byClass["Specificity"],
    con_LGBM$byClass["Precision"],
    con_LGBM$byClass["F1"],
    MCC_LGBM,
    pROC::auc(as.numeric(Y_test), as.numeric(lightGBM_Predictions)),
    LGBM_pr$auc.integral,
    con_LGBM$table[[1]],
    con_LGBM$table[[2]],
    con_LGBM$table[[3]],
    con_LGBM$table[[4]])
)

write.csv(performanceTable, ".//performanceTable_new.csv", row.names = FALSE)
#######################################################################################################
#######################################################################################################
#######################################################################################################

performanceTable %>% 
  kable("latex", booktabs = T, digits = 2) %>% 
  kable_styling(position = "center", font_size = 7, latex_options = c("striped", "hold_position")) %>%
  row_spec(0, angle = 0) %>% 
  add_footnote(c("Note: The Logistic Regression and Random Forest model removes missing values from its final results and cannot be adequately \n compared with the other results. ", "MCC: Matthew's Correlation Coefficient \n AUC: Area Under the Curve \n AUPRC: Area Under the Precision Recall Curve \n TP: True Positive | FP: False Positive | FN: False Negative | TN: True Negative"), notation = "symbol")

#######################################################################################################
#######################################################################################################
#######################################################################################################

######################### PR Curves #####################################

NB_pr_curve <- NB_pr$curve %>% 
  data.frame() %>% 
  mutate(X4 = "Naive Bayes")

Logistic_pr_curve <- Logistic_pr$curve %>% 
  data.frame() %>% 
  mutate(X4 = "Logistic Regression")
classTree_pr_curve <- classTree_pr$curve %>% 
  data.frame() %>% 
  mutate(X4 = "Classification Tree")
RF_pr_curve <- RF_pr$curve %>% 
  data.frame() %>% 
  mutate(X4 = "Random Forest")

adaBoost_pr_curve <- adaBoost_pr$curve %>% 
  data.frame() %>% 
  mutate(X4 = "adaBoost")


XGB_pr_curve <- XGB_pr$curve %>% 
  data.frame() %>% 
  mutate(X4 = "XGBoost")

LGBM_pr_curve <- LGBM_pr$curve %>% 
  data.frame() %>% 
  mutate(X4 = "Light GBM")



prPlot <- bind_rows(
  NB_pr_curve,
  Logistic_pr_curve,
  classTree_pr_curve,
  RF_pr_curve,
  adaBoost_pr_curve,
  XGB_pr_curve,
  LGBM_pr_curve
) %>% 
  ggplot(aes(x = X1, y = X2, color = X4)) +
  geom_line() +
  scale_color_viridis_d(option = "D", name = "Model",
                        labels = c("Na??ve Bayes", "Logistic Regression", "Classification Tree", "Random Forest",
                                   "adaBoost", "XGBoost", "Light GBM")) +
  labs(title= "Precision-Recall Curves", 
       y = "Precision",
       x = "Recall") +
  scale_x_continuous(breaks = c(0, 0.5, 1), labels = c(0, 0.5, 1)) +
  scale_y_continuous(breaks = c(0, 0.5, 1), labels = c(0, 0.5, 1), limits = c(0, 1)) +
  theme_bluewhite() +
  theme(
    aspect.ratio = 1,
    legend.position = "none",
    legend.margin=margin(0,0,0,0),
    legend.box.margin=margin(-10,-10,-10,-10),
    plot.margin = margin(0.1, 0.1, 0.1, 0.1, "cm")
  )

prPlot
#######################################################################
######################### ROC Curves ##################################
library(pROC)
NB_roc <- roc(as.numeric(Y_test),as.numeric(NB_Predictions))
Logistic_roc <- roc( as.numeric(Y_test),as.numeric(Logistic_Predictions))
RF_roc <- roc(as.numeric(Y_test),as.numeric(RF_Predictions))
adaBoost_roc <- roc( as.numeric(Y_test),as.numeric(adaBoost_Predictions))
classTree_roc <- roc( as.numeric(Y_test),as.numeric(classTreePredictions))
LGBM_roc <- roc(as.numeric(Y_test),lightGBM_Predictions)
XGB_roc <- roc( as.numeric(Y_test),as.numeric(XGBpredictions))

roc_curves <- list(
  NB_roc,
  Logistic_roc,
  classTree_roc,
  RF_roc,
  adaBoost_roc,
  XGB_roc,
  LGBM_roc
)

rocPlot <- roc_curves %>% 
  ggroc(legacy.axes = TRUE, linetype = 1, breaks = c(0, 0.25, 0.5, 0.75, 1)) +
  geom_abline(show.legend = TRUE, alpha = 0.3) +
  scale_color_viridis_d(option = "D", name = "Model",
                        labels = c("Na??ve Bayes", "Logistic Regression",  "Classification Tree","Random Forest",
                                   "adaBoost", "XGBoost", "Light GBM")) +
  labs(title= "ROC Curves", 
       y = "Sensitivity",
       x = "1-Specificity") +
  scale_x_continuous(breaks = c(0, 0.5, 1), labels = c(0, 0.5, 1)) +
  scale_y_continuous(breaks = c(0, 0.5, 1), labels = c(0, 0.5, 1)) +
  theme_bluewhite() +
  theme(
    aspect.ratio = 1,
    legend.position = "left",
    legend.margin=margin(0,0,0,0),
    legend.box.margin=margin(-10,-10,-10,-10),
    plot.margin = margin(0.1, 0.1, 0.1, 0.1, "cm")
  )
#rm(rocPlot)
rocPlot
###########################################################################
dev.off()
(rocPlot + prPlot) + plot_annotation(title = "Algorithm Comparison - Model Performance", tag_levels = "A", theme = theme(plot.title = element_text(hjust = 0.5), plot.margin = margin(0.1, 0.1, 0.1, 0.1, "cm")))

ggsave("rocPRPlot_new.pdf")

