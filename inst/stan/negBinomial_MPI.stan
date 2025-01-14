functions{

	real exp_gamma_meanSd_lpdf(vector x_log, real m_log, real s){

    // This function is the  probability of the log gamma function
    // in case you have data that is aleady in log form

    real m = exp(m_log);
    real v = m + square(m) * s;
    real a = square(m) / v;
    real b = m / v;

		vector[rows(x_log)] jacob = x_log; //jacobian
		real norm_constant = a * log(b) -lgamma(a);
		real a_minus_1 = a-1;
		return sum( jacob ) + norm_constant * rows(x_log) + sum(  x_log * a_minus_1 - exp(x_log) * b ) ;

	}

	real exp_gamma_meanSd_rng(real m_log, real s){
	  // This function takes care of the two prior choice
	  // without complicating too much the model itself

    real m = exp(m_log);
    real v = m + square(m) * s;
    real a = square(m) / v;
    real b = m / v;

	  return log(gamma_rng(a, b));
	}

	vector[] get_reference_parameters_MPI(int n_shards, int M, int[] G_per_shard, int[,] G_ind, matrix lambda_log, vector sigma, vector exposure_rate){

		int S = rows(exposure_rate);
		vector[(M*S) + M + S] lambda_sigma_exposure_MPI[n_shards];

		for( i in 1:n_shards ) {

			int size_buffer = ((M*S) + M) - ((G_per_shard[i]*S) + G_per_shard[i]) ;
		  vector[ size_buffer] buffer = rep_vector(0.0,size_buffer);

			lambda_sigma_exposure_MPI[i] =
	  		append_row(
	  		  append_row(
		  		    append_row(
		  		    	to_vector(lambda_log[,G_ind[i, 1:G_per_shard[i]]]),
		      		  sigma[G_ind[i, 1:G_per_shard[i]]]
		      		),
	      		buffer
	      	),
	      	exposure_rate
	      );
		}

		return(lambda_sigma_exposure_MPI);
	}

	vector lp_reduce( vector global_parameters , vector local_parameters , real[] real_data , int[] int_data ) {

		real lp;

		// Integer data unpack
	 	int M = int_data[1];
	 	int N = int_data[2];
	 	int S = int_data[3];
	 	int G_per_shard = int_data[4];
	 	int symbol_end[M+1] = int_data[(4+1):(4+1+M)];
	 	int sample_idx[N] = int_data[(4+1+M+1):(4+1+M+1+N-1)];
	 	int counts[N] = int_data[(4+1+M+1+N-1+1):(4+1+M+1+N-1+N)];

	 	// Data to exclude for outliers
	 	int size_exclude = int_data[(4+1+M+1+N-1+N+1)];
		int to_exclude[size_exclude] = int_data[(4+1+M+1+N-1+N+1+1):(4+1+M+1+N-1+N+1+size_exclude)]; // we are lucky for packaging it is the last variabe

		// Parameters unpack
	 	vector[G_per_shard*S] lambda_MPI = local_parameters[1:(G_per_shard*S)];
	 	vector[G_per_shard] sigma_MPI = local_parameters[((G_per_shard*S)+1):((G_per_shard*S) + G_per_shard)];
	 	vector[S] exposure_rate = local_parameters[(((M*S) + M)+1):rows(local_parameters)];

		// Vectorise lpmf
		//vector[symbol_end[G_per_shard+1]] lambda_MPI_c;
		vector[symbol_end[G_per_shard+1]] sigma_MPI_c;
		for(g in 1:G_per_shard){
			int how_many = symbol_end[g+1] - (symbol_end[g]);
			//lambda_MPI_c[(symbol_end[g]+1):symbol_end[g+1]] = rep_vector(lambda_MPI[g], how_many);
			sigma_MPI_c [(symbol_end[g]+1):symbol_end[g+1]] = rep_vector(sigma_MPI[g],  how_many);
		}

		lp =
			neg_binomial_2_log_lpmf(
    		counts[1:symbol_end[G_per_shard+1]] |
    		exposure_rate[sample_idx[1:symbol_end[G_per_shard+1]]] +
    		lambda_MPI,
	    	sigma_MPI_c
    	) -

    	(
    		// Exclude outliers by subtracting probability, if needed
    		size_exclude > 0 ?
    		neg_binomial_2_log_lpmf(
	    		counts[1:symbol_end[G_per_shard+1]][to_exclude] |
	    		exposure_rate[sample_idx[1:symbol_end[G_per_shard+1]]][to_exclude] +
	    		lambda_MPI[to_exclude],
		    	sigma_MPI_c[to_exclude]
	    	) :
	    	0
    	);

		// Return
		return [lp]';

  }

matrix merge_coefficients(row_vector intercept, row_vector alpha_sub_1, matrix alpha_2,  int C, int S, int G){
	matrix[C,G] my_alpha;


	if(C==1)
		my_alpha = to_matrix(intercept);
	else if(C>1)
		my_alpha =
			append_row(
				append_row(
					intercept,
					append_col(alpha_sub_1, rep_row_vector(0.0, G-cols(alpha_sub_1)))
				),
				append_col(alpha_2, rep_matrix(0.0, rows(alpha_2), G-cols(alpha_2)))
			);

	return my_alpha;
}

}
data {

	// Reference matrix inference
  int<lower=0> N;
  int<lower=0> M;
	int<lower=0> G;
	int<lower=0> S;
  int n_shards;
	int<lower=0> counts[n_shards, N];
	int<lower=0> symbol_end[n_shards, M+1];
	int<lower=0> G_ind[n_shards, M];
	int<lower=0> sample_idx[n_shards, N];
	int<lower=0> G_per_shard[n_shards];
	int<lower=0> G_per_shard_idx[n_shards + 1];

	int<lower=0> CP; // Counts package size
  int<lower=0> counts_package[n_shards, CP];

	int<lower=1> C; // Covariates
	matrix[S,C] X; // Design matrix

	real<lower=0> lambda_mu_mu;

	int<lower=0> how_many_to_check;

	// For better adaptation
	real exposure_rate_multiplier;
	real intercept_shift_scale[2];

	// Truncation
	real<lower=0> truncation_compensation;

}
transformed data {

  vector[0] global_parameters;
  real real_data[n_shards, 0];

}
parameters {


  // Overall properties of the data
  real lambda_mu_raw; // So is compatible with logGamma prior
  real<lower=0> lambda_sigma;
  real lambda_skew;

  vector[S] exposure_rate_raw;

  // Gene-wise properties of the data
  row_vector[G] intercept;
  row_vector[how_many_to_check] alpha_sub_1;
  matrix[max(0, C-2),how_many_to_check] alpha_2; // Linear model for calculating lambda_log
  vector[G] sigma_raw;

  // Signa linear model

  real<upper=0> sigma_slope;
  real sigma_intercept;
  real<lower=0>sigma_sigma;

}
transformed parameters {

	// For better adaptation
	real lambda_mu = lambda_mu_raw + lambda_mu_mu;
	//row_vector[G] intercept = (intercept_raw * intercept_shift_scale[2]) + intercept_shift_scale[1];
	vector[S] exposure_rate = exposure_rate_raw * exposure_rate_multiplier;

  // Sigma
  vector[G] sigma = 1.0 ./ exp(sigma_raw) ;
	matrix[C,G] alpha = merge_coefficients(intercept, alpha_sub_1, alpha_2,  C,  S,  G);
	matrix[S,G] lambda_log_param = X * alpha;


}

model {

  lambda_mu_raw ~ normal(0,2);
  lambda_sigma ~ normal(0,2);
	lambda_skew ~ normal(0,1);

  sigma_intercept ~ normal(0,2);
  sigma_slope ~ normal(0,2);
  sigma_sigma ~ normal(0,2);

  // Gene-wise properties of the data
  to_vector(intercept) ~ skew_normal(lambda_mu,lambda_sigma, lambda_skew);
  if(C>=2) alpha_sub_1 ~ double_exponential(0,1);
	if(C>=3) to_vector(alpha_2) ~ normal(0,2.5);

  sigma_raw ~ normal(sigma_slope * alpha[1,] + sigma_intercept,sigma_sigma);

  // Exposure prior
  exposure_rate_raw ~ normal(0,1);
  sum(exposure_rate_raw) ~ normal(0, 0.001 * S);

	//Gene-wise properties of the data
	target += sum(map_rect(
		lp_reduce ,
		global_parameters ,
		get_reference_parameters_MPI(
			n_shards,
			M,
			G_per_shard,
			G_ind,
			lambda_log_param,
			sigma,
			exposure_rate
		),
		real_data,
		counts_package
	));


	// target += sum(lp_reduce(
	// 	global_parameters,
	// 	get_reference_parameters_MPI(
	// 		n_shards,
	// 		M,
	// 		G_per_shard,
	// 		G_ind,
	// 		lambda_log_param,
	// 		sigma,
	// 		exposure_rate
	// 	)[1],
	// 	real_data[1],
	// 	counts_package[1]
	// ));

}
generated quantities{
	vector[G] counts_rng[S];

	for(g in 1:G) for(s in 1:S)
		counts_rng[s,g] =	neg_binomial_2_log_rng(exposure_rate[s] + lambda_log_param[s,g],	sigma[g] * truncation_compensation);

}
