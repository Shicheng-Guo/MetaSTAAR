#' Generating summary statistics file using MetaSTAAR_worker
#'
#' The \code{MetaSTAAR_worker_sumstat} function takes in genotype, the object
#' from fitting the null model, and variant information (unique identifier)
#' to generate the summary statistics file for the given variant-set.
#' @param genotype an n*p genotype matrix (dosage matrix) of the target sequence,
#' where n is the sample size and p is the number of genetic variants.
#' @param obj_nullmodel an object from fitting the null model, which is the
#' output from either \code{\link{fit_null_glm}} function for unrelated samples or
#' \code{\link{fit_null_glmmkin}} function for related samples in the \code{\link{STAAR}} package.
#' @param variant_info a data frame or matrix of variant information (unique identifier)
#' with p rows (listed in the same order as the columns of \code{genotype}) and should contain
#' the following 4 columns: chromosome (chr), position (pos), reference allele (ref), and alternative allele (alt).
#' @return \code{sumstat}: the data frame of all variants in the variant-set (the summary statistics file),
#' including the following information: chromosome (chr), position (pos), reference allele (ref),
#' alternative allele (alt), alternative allele count (alt_AC), minor allele count (MAC),
#' minor allele frequency (MAF), study sample size (N), score statistic (U), variance (V), and
#' the (low-rank decomposed) dense component of the covariance file.

MetaSTAAR_worker_sumstat <- function(genotype,obj_nullmodel,variant_info){

  if(class(genotype) != "matrix" && !(!is.null(attr(class(genotype), "package")) && attr(class(genotype), "package") == "Matrix")){
    stop("genotype is not a matrix!")
  }

  if(!is.null(attr(class(genotype), "package")) && attr(class(genotype), "package") == "Matrix"){
    genotype <- as.matrix(genotype)
  }

  if(dim(genotype)[2] != dim(variant_info)[1]){
    stop(paste0("Dimensions don't match for genotype and variant_info!"))
  }

  N <- dim(genotype)[1]
  alt_AC <- as.integer(colSums(2 - genotype))
  MAC <- as.integer(pmin(alt_AC, 2 * N - alt_AC))
  genotype <- matrix_flip(genotype)
  MAF <- genotype$MAF
  variant_label <- as.vector(MAF>0)
  Geno <- genotype$Geno[,variant_label,drop=FALSE]
  Geno <- as(Geno,"dgCMatrix")
  rm(genotype)
  gc()

  if(obj_nullmodel$relatedness){
    if(!obj_nullmodel$sparse_kins){
      stop(paste0("Please use a sparse genetic relatedness matrix when fitting the null model!"))
    }
  }else{
    if(obj_nullmodel$family[1] == "binomial"){
      obj_nullmodel$Sigma_i <- Diagonal(x = obj_nullmodel$weights)
    }else if(obj_nullmodel$family[1] == "gaussian"){
      obj_nullmodel$Sigma_i <- Diagonal(length(obj_nullmodel$y)) / summary(obj_nullmodel)$dispersion
    }
    obj_nullmodel$Sigma_iX <- obj_nullmodel$Sigma_i %*% model.matrix(obj_nullmodel)
    obj_nullmodel$cov <- solve(t(model.matrix(obj_nullmodel)) %*% obj_nullmodel$Sigma_i %*% model.matrix(obj_nullmodel))
    obj_nullmodel$scaled.residuals <- (obj_nullmodel$y - obj_nullmodel$fitted.values) / summary(obj_nullmodel)$dispersion
  }

  GTSinvX_cov <- as(t(Geno) %*% obj_nullmodel$Sigma_iX,"matrix") %*% sqrtm(obj_nullmodel$cov)
  #V <- diag(t(Geno) %*% obj_nullmodel$Sigma_i %*% Geno - GTSinvX_cov %*% t(GTSinvX_cov))
  V <- colSums(Geno * (obj_nullmodel$Sigma_i %*% Geno)) - rowSums(GTSinvX_cov^2) # faster for large no. variants
  U <- as.vector(t(Geno) %*% obj_nullmodel$scaled.residuals)
  rm(Geno)
  gc()

  sumstat <- data.frame(variant_info[,c("chr","pos","ref","alt")],alt_AC,MAC,MAF,N)
  sumstat <- sumstat[variant_label,]
  sumstat <- cbind(sumstat,U,V,GTSinvX_cov)

  return(sumstat)
}

