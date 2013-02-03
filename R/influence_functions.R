#' @export
leverage <- function(object, ...){
  UseMethod("leverage", object)
}

#' @export
leverage.default <- function(object, ...){
  stop(paste("there is no leverage() method for objects of class",
             paste(class(object), collapse=", ")))
}

#' @export
covratio <- function(object, ...){
  UseMethod("covratio", object)
}

#' @export
covratio.default <- function(object, ...){
  stop(paste("there is no covratio() method for objects of class",
             paste(class(object), collapse=", ")))
}

#' @export
covratio.lm <- function(object, ...){
  function (object, infl = lm.influence(object, do.coef = FALSE), 
            res = weighted.residuals(object)) 
  {
    n <- nrow(qr.lm(object)$qr)
    p <- object$rank
    omh <- 1 - infl$hat
    e.star <- res/(infl$sigma * sqrt(omh))
    e.star[is.infinite(e.star)] <- NaN
    1/(omh * (((n - p - 1) + e.star^2)/(n - p))^p)
  }
}

#' @export
covtrace <- function(object, ...){
  UseMethod("covtrace", object)
}

#' @export
covtrace.default <- function(object, ...){
  stop(paste("there is no covtrace() method for objects of class",
             paste(class(object), collapse=", ")))
}

#' @export
mdffits <- function(object, ...){
  UseMethod("mdffits", object)
}

#' @export
mdffits.default <- function(object, ...){
  stop(paste("there is no mdffits() method for objects of class",
             paste(class(object), collapse=", ")))
}

#' @export
rvc <- function(object, ...){
  UseMethod("rvc", object)
}

#' @export
rvc.default <- function(object, ...){
  stop(paste("there is no rvc() method for objects of class",
             paste(class(object), collapse=", ")))
}


#' Leverage for HLMs
#' 
#' This function calculates the leverage of
#' a hierarchical linear model fit by \code{lmer}. 
#' 
#' @export
#' @method leverage mer
#' @S3method leverage mer
#' @aliases leverage
#' @param object fitted object of class \code{mer}
#' @param level the level at which the leverage should be calculated: either
#'   1 for observation level leverage or the name of the grouping factor 
#'   (as defined in \code{flist} of the \code{mer} object) for group level
#'   leverage. \code{leverage} assumes that the grouping factors are unique;
#'   thus, if IDs are repeated within each unit, unique IDs must be generated 
#'   by the user prior to use of \code{leverage}.
#' @param ... do not use
#' @references 
#'   Demidenko, E., & Stukel, T. A. (2005) 
#'   Influence analysis for linear mixed-effects models. 
#'   \emph{Statistics in Medicine}, \bold{24}(6), 893--909.
#' @author Adam Loy \email{aloy@@iastate.edu}
#' @keywords models regression
#' @export
#' @seealso \code{\link{cooks.distance.mer}}, \code{\link{mdffits.mer}},
#' \code{\link{covratio.mer}}, \code{\link{covtrace.mer}}, \code{\link{rvc.mer}}  
#' 
#' @examples
#' data(sleepstudy, package = 'lme4')
#' fm <- lmer(Reaction ~ Days + (Days | Subject), sleepstudy)
#' 
#' # Observation level leverage
#' lev1 <- leverage.mer(fm, level = 1)
#' head(lev1)
leverage.mer <- function(object, level, ...) {
  if(!is(object, "mer")) stop("object must be of class 'mer'")
  if(object@dims[["nest"]] == 0) {
    stop("leverage.mer has not yet been implemented for models with 
         crossed random effects")
  }
  if(!level %in% c( 1, names(getME(object, "flist")))) {
    stop("level can only be 1 or a grouping factor from the fitted model.")
  }
  
  X <- getME(object, "X")
  # Z <- BlockZ(object)
  
  n     <- nrow(X)
  nt    <- object@dims[["nt"]]  # number of random-effects terms in the model
  ngrps <- unname( summary(object)@ngrps )
  
  vc   <- VarCorr(object)
  # D  <- kronecker( Diagonal(ngrps), bdiag(vc) )
  ZDZt <- attr(vc, "sc")^2 * crossprod( getME(object, "A") )
  R    <- Diagonal( n = n, x = attr(vc, "sc")^2 )
  
  V      <- ZDZt + R
  V.chol <- chol( V )
  Vinv   <- chol2inv( V.chol )
  
  xvix.inv <- attr(vc, "sc")^2 * chol2inv(getME(object, "RX"))
  
  H1 <- X %*% xvix.inv %*% t(X) %*% Vinv
  H2 <- ZDZt %*% (Diagonal( n = n ) - H1)
  
  diag.H1 <- diag(H1)
  diag.H2 <- diag(H2)
  
  if(level == 1) {
    lev1 <- data.frame(fixef = diag.H1, ranef =  diag.H2)
    class(lev1) <- "leverage"
  } else {
    flist   <- data.frame( getME(object, "flist")[, level] )
    grp.lev <- data.frame( fixef = aggregate(diag.H1, flist, mean)[,2], 
                           ranef = aggregate(diag.H2, flist, mean)[,2] )
    class(grp.lev) <- "leverage"
  }
  
  if(level == 1) return(lev1)
  if(level != 1) return(grp.lev)
}


#' Influence on fixed effects of HLMs
#'
#' These functions calculate measures of the change in the fixed effects
#' estimates based on the deletetion of an observation, or group of 
#' observations, for a hierarchical linear model fit using \code{lmer}.
#' 
#' @details
#' Both Cook's distance and MDFFITS measure the change in the 
#' fixed effects estimates based on the deletion of a subset of observations. 
#' The key difference between the two diagnostics is that Cook's distance uses
#' the variance-covariance matrix for the fixed effects from the original
#' model while MDFFITS uses the variance-covariance matrix from the deleted 
#' model. 
#' 
#' @note
#' Because MDFFITS requires the calculation of the variance-covarinace matrix
#' for the fixed effects for every model, it will be slower.
#'
#'@export
#'@method cooks.distance mer
#'@S3method cooks.distance mer
#'@aliases cooks.distance
#'@param model fitted model of class \code{mer}
#'@param group variable used to define the group for which cases will be
#'deleted.  If \code{group = NULL}, then individual cases will be deleted.
#'@param delete index of individual cases to be deleted. To delete specific 
#' observations the row number must be specified. To delete higher level
#'units the group ID and \code{group} parameter must be specified.
#' If \code{delete = NULL} then all cases are iteratively deleted.
#' @param ... do not use
#'@author Adam Loy \email{aloy@@iastate.edu}
#'@references
#' Christensen, R., Pearson, L., & Johnson, W. (1992) 
#' Case-deletion diagnostics for mixed models. \emph{Technometrics}, \bold{34}(1), 
#' 38--45.
#'   
#' Schabenberger, O. (2004) Mixed Model Influence Diagnostics,
#' in \emph{Proceedings of the Twenty-Ninth SAS Users Group International Conference},
#' SAS Users Group International.
#' 
#'@keywords models regression
#' @seealso \code{\link{leverage.mer}},
#' \code{\link{covratio.mer}}, \code{\link{covtrace.mer}}, \code{\link{rvc.mer}}
#' @examples 
#' data(Exam, package = 'mlmRev')
#' fm <- lmer(normexam ~ standLRT * schavg + (standLRT | school), Exam)
#' 
#' # Cook's distance for individual observations
#' cd.lev1 <- cooks.distance(fm)
#' 
#' # Cook's distance for each school
#' cd.school <- cooks.distance(fm, group = "school")
#' 
#' # Cook's distance when school 1 is deleted
#' cd.school1 <- cooks.distance(fm, group = "school", delete = 1)
#' 
cooks.distance.mer <- function(model, group = NULL, delete = NULL, ...) {
  if(!is(model, "mer")) stop("model must be of class 'mer'")
  if(!is.null(group)) {
    if(!group %in% names(getME(model, "flist"))) {
      stop(paste(group, "is not a valid grouping factor for this model."))
    }
  }
  if(!model@dims["LMM"]){
    stop("cooks.distance is currently not implemented for GLMMs.")
  }
  
  # Extract key pieces of the model
  mats <- .mer_matrices(model)
  
  betaHat <- with(mats, XVXinv %*% t(X) %*% Vinv %*% Y)
  
  # Obtaining the building blocks
  if(is.null(group) & is.null(delete)) {
    calc.cooksd <- .Call("cooksdObs", y_ = mats$Y, X_ = as.matrix(mats$X), 
                         Vinv_ = as.matrix(mats$Vinv), 
                         XVXinv_ = as.matrix(mats$XVXinv), 
                         beta_ = as.matrix(betaHat), PACKAGE = "HLMdiag")
    res <- calc.cooksd[[1]]
    attr(res, "beta_cdd") <- calc.cooksd[[2]]
  }
  
  else{
    e <- with(mats, Y - X %*% betaHat)
    
    if( !is.null(group) ){
      grp.names <- unique( mats$flist[, group] )
      
      if( is.null(delete) ){
        del.index <- lapply(1:mats$ngrps[group], 
                            function(x) {
                              ind <- which(mats$flist[, group] == grp.names[x]) - 1
                            })
      } else{
        del.index <- list( which(mats$flist[, group] %in% delete) - 1 )
      }
    } else{
      del.index <- list( delete - 1 )
    }
    
    calc.cooksd <- .Call("cooksdSubset", index = del.index, 
                         X_ = as.matrix(mats$X), 
                         P_ = as.matrix(mats$P), 
                         Vinv_ = as.matrix(mats$Vinv), 
                         XVXinv_ = as.matrix(mats$XVXinv), 
                         e_ = as.numeric(e), PACKAGE = "HLMdiag")
    
    res <- calc.cooksd[[1]]
    attr(res, "beta_cdd") <- calc.cooksd[[2]] 
  }
  
  class(res) <- "fixef.dd"
  return(res)
}

print.fixef.dd <- function(x, ...) {
  attributes(x) <- NULL
  print(x, ...)
}

plot.fixef.dd <- function(x, ...) {
  
}

print.vcov.dd <- function(x, ...) { print(unclass(x), ...) }


#' @export
#' @rdname cooks.distance.mer
#' @method mdffits mer
#' @S3method mdffits mer
#' @aliases mdffits
#' @param object fitted object of class \code{mer}
#' @examples
#'   
#' # MDFFITS  for individual observations
#' m1 <- mdffits(fm)
#' 
#' # MDFFITS for each school
#' m.school <- mdffits(fm, group = "school")
mdffits.mer <- function(object, group = NULL, delete = NULL, ...) {
  if(!is(object, "mer")) stop("object must be of class 'mer'")
  if(!is.null(group)) {
    if(!group %in% names(getME(object, "flist"))) {
      stop(paste(group, "is not a valid grouping factor for this model."))
    }
  }
  if(!object@dims["LMM"]){
    stop("mdffits is currently not implemented for GLMMs.")
  }
  
  # Extract key pieces of the model
  mats <- .mer_matrices(object)
  
  betaHat <- with(mats, XVXinv %*% t(X) %*% Vinv %*% Y)
  e <- with(mats, Y - X %*% betaHat)
  
  if( !is.null(group) ){
    grp.names <- unique( mats$flist[, group] )
    
    if( is.null(delete) ){
      del.index <- lapply(1:mats$ngrps[group], 
                          function(x) {
                            ind <- which(mats$flist[, group] == grp.names[x]) - 1
                          })
    } else{
      del.index <- list( which(mats$flist[, group] %in% delete) - 1 )
    }
  } else{
    if( is.null(delete) ){
      del.index <- split(0:(mats$n-1), 0:(mats$n-1))
    } else { del.index <- list( delete - 1 ) }
  }
  
  calc.mdffits <- .Call("mdffitsSubset", index = del.index, X_ = mats$X, 
                        P_ = mats$P, Vinv_ = as.matrix(mats$Vinv), 
                        XVXinv_ = as.matrix(mats$XVXinv), 
                        e_ = as.numeric(e), PACKAGE = "HLMdiag")
  res <- calc.mdffits[[1]]
  attr(res, "beta_cdd") <- calc.mdffits[[2]] 
  
  class(res) <- "fixef.dd"
  return(res)
}


#' Influence on precision of fixed effects in HLMs
#'
#' These function calculate measures of the change in the variance-covariance
#' matrices for the fixed effects based on the deletetion of an
#' observation, or group of observations, for a hierarchical 
#' linear model fit using \code{lmer}.
#' 
#' @details
#'  Both the covariance ratio (\code{covratio}) and the covariance trace
#'  (\code{covtrace}) measure the change in the variance-covariance matrix
#'  of the fixed effects based on the deletion of a subset of observations.
#'  The key difference is how the variance covariance matrices are compared:
#'  \code{covratio} compares the ratio of the determinants while \code{covtrace}
#'  compares the ratio of the traces. 
#'  
#'@export
#'@method covratio mer
#'@S3method covratio mer
#'@aliases covratio
#'@param object fitted object of class \code{mer}
#'@param group variable used to define the group for which cases will be
#'deleted.  If \code{group = NULL}, then individual cases will be deleted.
#'@param delete index of individual cases to be deleted. To delete specific 
#' observations the row number must be specified. To delete higher level
#'units the group ID and \code{group} parameter must be specified.
#' If \code{delete = NULL} then all cases are iteratively deleted.
#'@param ... do not use
#' @return If \code{delete = NULL} then a vector corresponding to each deleted
#' observation/group is returned.
#' 
#' If \code{delete} is specified then a single value is returned corresponding
#' to the deleted subset specified.
#'@author Adam Loy \email{aloy@@iastate.edu}
#'@references
#' Christensen, R., Pearson, L., & Johnson, W. (1992) 
#' Case-deletion diagnostics for mixed models. \emph{Technometrics}, \bold{34}(1), 
#' 38--45.
#'   
#' Schabenberger, O. (2004) Mixed Model Influence Diagnostics,
#' in \emph{Proceedings of the Twenty-Ninth SAS Users Group International Conference},
#' SAS Users Group International.
#' 
#'@keywords models regression
#' @seealso \code{\link{leverage.mer}}, \code{\link{cooks.distance.mer}}
#' \code{\link{mdffits.mer}}, \code{\link{rvc.mer}}
#'  
#' @examples
#' data(Exam, package = 'mlmRev')
#' fm <- lmer(normexam ~ standLRT * schavg + (standLRT | school), Exam)
#' 
#' # covratio for individual observations
#' cr1 <- covratio(fm)
#' 
#' # covratio for school-level deletion
#' cr2 <- covratio(fm, group = "school")
covratio.mer <- function(object, group = NULL, delete = NULL, ...) {
  if(!is(object, "mer")) stop("object must be of class 'mer'")
  if(!is.null(group)) {
    if(!group %in% names(getME(object, "flist"))) {
      stop(paste(group, "is not a valid grouping factor for this model."))
    }
  }
  if(!object@dims["LMM"]){
    stop("covratio is currently not implemented for GLMMs.")
  }
  
  # Extract key pieces of the model
  mats <- .mer_matrices(object)
  
  if( !is.null(group) ){
    grp.names <- unique( mats$flist[, group] )
    
    if( is.null(delete) ){
      del.index <- lapply(1:mats$ngrps[group], 
                          function(x) {
                            ind <- which(mats$flist[, group] == grp.names[x]) - 1
                          })
    } else{
      del.index <- list( which(mats$flist[, group] %in% delete) - 1 )
    }
  } else{
    if( is.null(delete) ){
      del.index <- split(0:(mats$n-1), 0:(mats$n-1))
    } else { del.index <- list( delete - 1 ) }
  }
  
  res <- .Call("covratioCalc", index = del.index, X_ = mats$X, P_ = mats$P, 
               Vinv_ = as.matrix(mats$Vinv), XVXinv_ = as.matrix(mats$XVXinv), 
               PACKAGE = "HLMdiag")
  
  class(res) <- "vcov.dd"
  return(res)
}



#'@export
#'@rdname covratio.mer
#'@method covtrace mer
#'@S3method covtrace mer
#'@aliases covtrace
#' @examples
#' # covtrace for individual observations
#' ct1 <- covtrace(fm)
#' 
#' # covtrace for school-level deletion
#' ct2 <- covtrace(fm, group = "school")
covtrace.mer <- function(object, group = NULL, delete = NULL, ...) {
  if(!is(object, "mer")) stop("object must be of class 'mer'")
  if(!is.null(group)) {
    if(!group %in% names(getME(object, "flist"))) {
      stop(paste(group, "is not a valid grouping factor for this model."))
    }
  }
  if(!object@dims["LMM"]){
    stop("covtrace is currently not implemented for GLMMs or NLMMs.")
  }
  
  # Extract key pieces of the model
  mats <- .mer_matrices(object)
  
  if( !is.null(group) ){
    grp.names <- unique( mats$flist[, group] )
    
    if( is.null(delete) ){
      del.index <- lapply(1:mats$ngrps[group], 
                          function(x) {
                            ind <- which(mats$flist[, group] == grp.names[x]) - 1
                          })
    } else{
      del.index <- list( which(mats$flist[, group] %in% delete) - 1 )
    }
  } else{
    if( is.null(delete) ){
      del.index <- split(0:(mats$n-1), 0:(mats$n-1))
    } else { del.index <- list( delete - 1 ) }
  }
  
  res <- .Call("covtraceCalc", index = del.index, X_ = mats$X, P_ = mats$P, 
               Vinv_ = as.matrix(mats$Vinv), XVXinv_ = as.matrix(mats$XVXinv), 
               PACKAGE = "HLMdiag")
  
  return(res)
}

#' Relative variance change for mixed/hierarchical linear models
#' 
#' This function calculates the relative variance change (RVC) of
#' mixed/hierarchical linear models fit via \code{lmer}.
#' 
#' @export
#' @method rvc mer
#' @S3method rvc mer
#' @aliases rvc
#'@param object fitted object of class \code{mer}
#'@param group variable used to define the group for which cases will be
#'deleted.  If \code{group = NULL}, then individual cases will be deleted.
#'@param delete index of individual cases to be deleted. To delete specific 
#' observations the row number must be specified. To delete higher level
#'units the group ID and \code{group} parameter must be specified.
#' If \code{delete = NULL} then all cases are iteratively deleted.
#'@param ... do not use
#' @return If \code{delete = NULL} a matrix with columns corresponding to the variance 
#' components of the model and rows corresponding to the deleted 
#' observation/group is returned. 
#' 
#' If \code{delete} is specified then a named vector is returned.
#' 
#' The residual variance is named \code{sigma2} and the other variance 
#' componenets are named \code{D**} where the trailing digits give the
#' position in the covariance matrix of the random effects.
#' 
#'@author Adam Loy \email{aloy@@iastate.edu}
#'@references
#' Dillane, D. (2005) Deletion Diagnostics for the Linear Mixed Model. 
#' Ph.D. thesis, Trinity College Dublin
#' 
#' @keywords models regression
#' @seealso \code{\link{leverage.mer}}, 
#' \code{\link{cooks.distance.mer}}, \code{\link{mdffits.mer}},
#' \code{\link{covratio.mer}}, \code{\link{covtrace.mer}}
rvc.mer <- function(object, group = NULL, delete = NULL, ...) {
    delete <- case_delete(object, group = group, type = "varcomp", delete = delete)
    return( rvc(delete) )
}