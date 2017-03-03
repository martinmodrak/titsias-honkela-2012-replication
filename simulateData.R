require(deSolve);
require(abind)

proteinODE <- function(t, state, parameters)
{
  with(as.list(c(state, parameters)), {
    dX = regulator(t) - degradation * x;
    
    list(dX) 
  })
}

targetODE <- function(t, state, parameters)
{
  with(as.list(c(state, parameters)), {
    regulatoryInput = bias + weight * log(protein(t));
    dX = sensitivity/(1 + exp(-regulatoryInput)) - degradation * x;
    
    list(dX)
  })
}

bindReplicates <- function(a,b) {
  dimsA = dim(a);
  if(length(dimsA) == 2) {
    a = array(a,c(1,dimsA[1],dimsA[2]))
  }
  abind(a,b, along = 1);
}

simulateData <- function(regulatorProfile, numIntegrationPoints = 4,numTargets = 4, numReplicates = 3)
{
  time = 1:length(regulatorProfile);
  
  regulatorReplicates = array(0, c(numReplicates, length(time)));
  regulatorReplicates[1,] = regulatorProfile;
  for(i in 2:numReplicates)
  {
    regulatorReplicates[i,] = regulatorProfile + rnorm(length(time), 0,1);
  }
  
  step = 1/numIntegrationPoints;
  integrationTime = seq(from = 1, to = length(regulatorProfile) + step, by = step);
  
  proteinDegradation = 0.4;#exp(rnorm(1, -0.5,2));
  proteinInitialLevel = 0.8;#exp(rnorm(1, -0.5,2));
  
  initialConditions = array(exp(rnorm(numTargets * numReplicates, -0.5,2)), c(numTargets, numReplicates));
  basalTranscription = exp(rnorm(numTargets, -0.5,2));
  degradation = exp(rnorm(numTargets, -0.5,2));
  sensitivity = exp(rnorm(numTargets, -0.5,2));
  
  bias = rnorm(numTargets, 0, 1);
  
  interactionWeights = rnorm(numTargets, 0, 2);
  
  sigmaGenerator <- function(len) {abs(rcauchy(len,0,0.1)) + 0.00001};
  
  regulatorSigma = array(0, c(numReplicates, length(time)));
  regulatorObserved = array(0, c(numReplicates, length(time)));
  for(i in 1:numReplicates) 
  {
    regulatorSigma[i,] =sigmaGenerator(length(time));
    regulatorObserved[i,] = regulatorReplicates[i,] + (rnorm(length(time)) * regulatorSigma[i,]);
  }

  
  regulatorProtein = array(0, c(numReplicates, length(integrationTime)));
  for(i in 1:numReplicates) 
  {
    proteinODEParams = c(degradation = proteinDegradation, regulator = approxfun(time, regulatorReplicates[i,], rule=2));  
    regulatorProtein[i,] = ode( y = c(x = proteinInitialLevel), times = integrationTime, func = proteinODE, parms = proteinODEParams, method = "ode45")[,"x"];
  
  }
  
  regulatorProtein[regulatorProtein < 0.05] = 0.05;
  
  spots = character(numTargets + 1);
  spots[1] = "reg";

  targetValues = array(0, c(numTargets, numReplicates, length(time)));
  targetObserved = array(0, c(numTargets, numReplicates, length(time)));
  targetSigma = array(0, c(numTargets, numReplicates, length(time)));
  for(i in 1:numTargets)
  {

    for(j in 1:numReplicates)
    {
      params = c(degradation = degradation[i], bias = bias[i], sensitivity = sensitivity[i], weight = interactionWeights[i], protein = approxfun(integrationTime, regulatorProtein[j,], rule=2));  
      
      targetValues[i,j,] = ode( y = c(x = initialConditions[i,j]), times = time, func = targetODE, parms = params, method = "ode45")[,"x"];
      
      targetSigma[i,j,] = sigmaGenerator(length(time));
      
      targetObserved[i,j,] = targetValues[i,j,] + rnorm(length(time)) * targetSigma[i,j,]
      
    }    
    
    spots[i + 1] = paste0("t",i);
  }
  
  observed = bindReplicates(regulatorObserved, targetObserved);
  observed[observed <= 0.05] = 0.05;
  
  data = list(
    y = observed,
    yvar = bindReplicates(regulatorSigma, targetSigma),
    genes = spots,
    times = time,
    numReplicates = numReplicates,
    trueProtein = regulatorProtein,
    trueTargets = targetValues,
    targetSigma = targetSigma,
    proteinDegradation = proteinDegradation,
    params = list(
      initialConditions = initialConditions,
      degradation = degradation,
      basalTranscription = basalTranscription,
      sensitivity = sensitivity,
      weights = interactionWeights,
      bias = bias
    )
    , regulatorSpots = spots[1]
    , targetSpots = spots[2:(numTargets + 1)]
  )
}