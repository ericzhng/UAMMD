/*Raul P. Pelaez 2018. BDHI::FCM tests

All output is adimensional.



 */
#include"uammd.cuh"
#include"Interactor/ExternalForces.cuh"
#include"Interactor/Interactor.cuh"
#include"Integrator/BDHI/BDHI_EulerMaruyama.cuh"
#include"Integrator/BDHI/BDHI_FCM.cuh"

#include<iostream>

#include<vector>
#include<fstream>
#include<iomanip>
using namespace uammd;

real temperature, viscosity, rh, tolerance;

//FCM kernel M(\vec{r}) = f(r)·I + g(r)·\vec{r}\otimes\vec{r}/r^2
//M0 = f(0)
long double f(long double r){return (1.0/(8.0*M_PIl*viscosity*r)) * (  (1+2*rh*rh/(M_PIl*r*r))*erf(r*sqrt(M_PIl)/(2*rh)) - 2*rh/(M_PIl*r)*exp(-M_PIl*r*r/(4*rh*rh)) );}
long double g(long double r){ return (1.0/(8.0*M_PIl*viscosity*r)) * (  (1-6*rh*rh/(M_PIl*r*r))*erf(r*sqrt(M_PIl)/(2*rh)) + 6*rh/(M_PIl*r)*exp(-M_PIl*r*r/(4*rh*rh)) );}


//Self mobility with PBC corrections up to sixth order
long double computeM0PBC(double L){
  return  1.0l/(6.0l*M_PIl*viscosity*rh)*(1.0l-2.837297l*rh/L+(4.0l/3.0l)*M_PIl*pow(rh/L,3)-27.4l*pow(rh/L,6.0l));
}

//Pulls two particles agains each other, or just the first one if there is only one particle
class miniInteractor: public Interactor{
public:
  using Interactor::Interactor;
  real3 F;
  void sumForce(cudaStream_t st) override{
    auto force = pd->getForce(access::location::cpu, access::mode::write);
    force.raw()[0] = make_real4(F,0);
    if(pg->getNumberParticles()>1)
      force.raw()[1] = make_real4(real(-1.0)*F,0);    
  }
  real sumEnergy() override{return 0;}
};


using std::make_shared;
using std::endl;
//Self mobility deterministic test. Pull a particle with a force, measure its velocity.
void computeSelfMobilityMatrix(real3 L, double F, long double *M){
  int N = 1;
  auto sys = make_shared<System>();
  sys->rng().setSeed(0xabefa129f9173^time(NULL));
  for(int i = 0; i<10000; i++) sys->rng().next();
  auto pd = make_shared<ParticleData>(N, sys);
  auto pg = make_shared<ParticleGroup>(pd, sys, "All");

  Box box(L);
  BDHI::FCM::Parameters par;
  par.temperature = 0.0;
  par.viscosity = viscosity;
  par.hydrodynamicRadius = rh;
  par.dt = 0.01;
  par.box = box;
  par.tolerance = tolerance;
  
  auto bdhi = make_shared<BDHI::EulerMaruyama<BDHI::FCM>>(pd, pg, sys, par);

  auto inter= make_shared<miniInteractor>(pd, pg, sys, "puller");
  bdhi->addInteractor(inter);


  for(int i = 0; i<9;i++){M[i] = 0;}
  int Ntest = 10;  
  for(int i = 0; i<Ntest;i++){
    for(int alpha = 0; alpha<3;alpha++){
      double3 posprev;
      {
	auto pos = pd->getPos(access::location::cpu, access::mode::write);
	pos.raw()[0] = make_real4(make_real3(sys->rng().uniform3(-0.5, 0.5))*box.boxSize,0);
	posprev = make_double3(make_real3(pos.raw()[0]));
      }

      inter->F = F*make_real3(alpha==0, alpha==1, alpha==2);
      bdhi->forwardTime();
      double3 vel;
      {
	auto pos = pd->getPos(access::location::cpu, access::mode::read);  
	vel = (make_double3(make_real3(pos.raw()[0]))-posprev)/par.dt;
      }
      M[alpha+3*0] += vel.x/(F*double(Ntest));
      M[alpha+3*1] += vel.y/(F*double(Ntest));
      M[alpha+3*2] += vel.z/(F*double(Ntest));    
    }
  }
  sys->finish();
}

bool selfMobilityCubicBox_test(){

  int NL = 30;
  std::vector<real2> velocities(NL);

  real L_min = 8*rh;
  real L_max = 128*rh;

  double F = 1;
  long double M[9];
  std::ofstream Mout("selfMobilityCubicBox.test");
  fori(0, NL){
    real L = L_min + i*((L_max-L_min)/(real)(NL-1));
    computeSelfMobilityMatrix(make_real3(L), F, M);
    
    CudaCheckError();
   
    long double M0 = computeM0PBC(L);
    
    Mout<<std::setprecision(15)<<L/rh<<" ";
    //Substract 1 to the diagonal terms, which should be one so a matrix of zeroes should be printed
    //abs to be able to plot log
    for(int j=0; j<9; j++) Mout<<std::setprecision(15)<<abs((1*(j%3==j/3)-M[j]/M0))<<" ";
    Mout<<endl;
  }

  return true;
}

void computePairMobilityMatrix(real3 L, double F, real3 dist, long double *M){
  int N = 2;
  auto sys = make_shared<System>();
  sys->rng().setSeed(0xabefa129f9173^time(NULL));
  for(int i = 0; i<10000; i++) sys->rng().next();
  auto pd = make_shared<ParticleData>(N, sys);
  auto pg = make_shared<ParticleGroup>(pd, sys, "All");

  Box box(L);
  BDHI::FCM::Parameters par;
  par.temperature = 0.0;
  par.viscosity = viscosity;
  par.hydrodynamicRadius = rh;
  par.dt = 0.01;
  par.box = box;
  par.tolerance = tolerance;
  
  auto bdhi = make_shared<BDHI::EulerMaruyama<BDHI::FCM>>(pd, pg, sys, par);

  auto inter= make_shared<miniInteractor>(pd, pg, sys, "puller");
  bdhi->addInteractor(inter);


  for(int i = 0; i<9;i++){M[i] = 0;}
  int Ntest = 10;  
  for(int i = 0; i<Ntest;i++){
    for(int alpha = 0; alpha<3;alpha++){
      double3 posprev;
      {
	auto pos = pd->getPos(access::location::cpu, access::mode::write);
	real3 ori = make_real3(sys->rng().uniform3(-0.5, 0.5))*box.boxSize;
	pos.raw()[0] = make_real4(ori,0);
	pos.raw()[1] = make_real4(ori+dist,0);
	posprev = make_double3(make_real3(pos.raw()[1]));
      }

      inter->F = F*make_real3(alpha==0, alpha==1, alpha==2);
      bdhi->forwardTime();
      double3 vel;
      {
	auto pos = pd->getPos(access::location::cpu, access::mode::read);  
	vel = (make_double3(make_real3(pos.raw()[1]))-posprev)/par.dt;
      }
      M[alpha+3*0] += vel.x/(F*double(Ntest));
      M[alpha+3*1] += vel.y/(F*double(Ntest));
      M[alpha+3*2] += vel.z/(F*double(Ntest));
    }
  }
  sys->finish();
}

bool pairMobilityCubicBox_test(double dist){

  int NL = 20;

  real L_min = 2.1*dist;
  real L_max = 130*rh;

  Xorshift128plus rng;
  rng.setSeed(0x12ffdbae328f01^time(NULL));
  for(int i = 0; i<10000; i++) rng.next();
  real3 dir = make_real3(0);
  
  while(dir.x == 0 or dir.y == 0 or dir.z == 0) dir = make_real3(rng.gaussian3(0,1));	
  real3 rij = dist*dir/sqrt(dot(dir,dir));

  std::ofstream out("pairMobilityCubicBox.dist"+std::to_string(dist)+".test");
  double F = 1;
  long double M[9];

  double M_theo_Linf[9];
  out<<"#rij "<<rij.x<<" "<<rij.y<<" "<<rij.z<<endl;
  //When applying a force \vec{force_i} = (-1)^i·\hat{\beta} to particle i, the velocity of the other particle will be v_\alpha = M_{alpha\beta}(r)-M_{\alpha\beta}(0) = (f(r)-f(0))·\delta_{\alpha\beta}+ g(r)·r_\alpha*r_\beta/r^2
  for(int i=0; i<9; i++){ M_theo_Linf[i] = 0;}
  for(int i=0; i<3; i++){
    for(int j=0; j<3; j++){
      long double r = sqrt(dot(rij, rij)); 
      real *r01 = &rij.x;
      long double diadic = 0;
      if(r>0) diadic = r01[i]*r01[j]/(r*r);
      M_theo_Linf[3*i+j] = g(r)*diadic;
      long double fr = 1.0L/(6.0L*M_PIl*viscosity*rh);      
      if(r>1e-7*rh) fr = f(r)-fr;
      if(i==j) M_theo_Linf[3*i+j] += fr;


    }
  }
  
  fori(0, NL){
    real L = L_min + i*((L_max-L_min)/(real)(NL-1));
    out<<std::setprecision(15)<<L/rh<<" ";
    computePairMobilityMatrix(make_real3(L), F, rij, M);
    //With the correction this should print something converging to zero very fast for all terms
    //long double pbc_corr = computeM0PBC(L)*(6.0L*M_PIl*viscosity*rh);
    for(int j = 0; j<9; j++)    out<<abs(1.0l-M[j]/(M_theo_Linf[j]))<<" ";
    out<<endl;
  
    CudaCheckError();
  }
  return true;
}

bool pairMobility_q2D_test(double dist){

  int NL = 400;

  real L_min = 2.1*dist;
  real L_max = 200*rh;

  Xorshift128plus rng;
  rng.setSeed(0x12ffdbae328f01^time(NULL));
  for(int i = 0; i<10000; i++) rng.next();
  real3 dir = make_real3(0);
  
  while(dir.x == 0 or dir.y == 0 or dir.z == 0) dir = make_real3(rng.gaussian3(0,1));	
  real3 rij = dist*dir/sqrt(dot(dir,dir));

  std::ofstream out("pairMobility_q2D.dist"+std::to_string(dist)+".test");
  double F = 1;
  long double M[9];

  out<<"#rij "<<rij.x<<" "<<rij.y<<" "<<rij.z<<endl;
  real Lx = 32;
  fori(0, NL){
    real Lz = L_min + i*((L_max-L_min)/(real)(NL-1));
    out<<std::setprecision(15)<<Lz/rh<<" ";
    computePairMobilityMatrix(make_real3(Lx,Lx,Lz), F, rij, M);
    double M0 = 1.0/(6*M_PI*viscosity*rh);
    for(int j = 0; j<9; j++)  out<<M[j]/M0<<" ";
    out<<endl;
  
    CudaCheckError();
  }
  return true;
}

bool selfMobility_q2D_test(){
  
  int NL = 40;
  std::vector<real2> velocities(NL);

  real L_min = 8*rh;
  real L_max = 200*rh;

  double F = 1;
  long double M[9];
  std::ofstream Mout("selfMobility_q2D.test");
  std::ofstream Mtheoout("selfMobility_q2D.theo.test");
  fori(0, NL){
    real Lz = L_min + i*((L_max-L_min)/(real)(NL-1));
    real L = 32*rh;
    computeSelfMobilityMatrix(make_real3(L,L, Lz), F, M);
    
    CudaCheckError();
   
    long double M0 = 1.0L/(6.0L*M_PIl*viscosity*rh);
    //From eq 21 and 23 in Vögele, M., & Hummer, G. (2016). Divergent Diffusion Coefficients in Simulations of Fluids and Lipid Membranes. The Journal of Physical Chemistry B, 120(33), 8722–8732. doi:10.1021/acs.jpcb.6b05102
  
    double Mplane_near = M0 + M0/L*(M_PI*0.5*Lz/L - 4.3878);
    double Mplane_far = M0 + M0/Lz*(1.5*log(L/Lz) - 2.8897);
    
    double Mperp_near = M0 + M0/Lz*(3*log(L/Lz) - 2.77939);
    double Mperp_far = M0 - 2.9252/(6*M_PI*viscosity*L);

    Mout<<std::setprecision(15)<<Lz/rh<<" ";
    Mtheoout<<std::setprecision(15)<<Lz/rh<<" ";
    for(int j=0; j<9; j++) Mout<<std::setprecision(15)<<M[j]/M0<<" ";
    
    Mtheoout<<std::setprecision(15)<<Mplane_near/M0<<" "<<Mplane_far/M0<<" "<<Mperp_near/M0<<" "<<Mperp_far/M0<<endl;
    Mout<<endl;
  }

  return true;
}


bool idealParticlesDiffusion(int N, real3 L, std::string suffix = "test"){
  auto sys = make_shared<System>();
  sys->rng().setSeed(0x33dbff9f235ab^time(NULL));
  for(int i=0; i<10000; i++) sys->rng().next();
  
  auto pd = make_shared<ParticleData>(N, sys);
  auto pg = make_shared<ParticleGroup>(pd, sys, "All");

  Box box(L);
  BDHI::FCM::Parameters par;
  par.temperature = temperature;
  par.viscosity = viscosity;
  par.hydrodynamicRadius = rh;
  par.dt = 0.001;
  par.box = box;
  par.tolerance = tolerance;
  
  auto bdhi = make_shared<BDHI::EulerMaruyama<BDHI::FCM>>(pd, pg, sys, par);
  std::ofstream out("pos.noise.boxSize"+std::to_string(L.z)+".dt"+std::to_string(par.dt)+"."+suffix);
  {
    auto pos = pd->getPos(access::location::cpu, access::mode::write);
    fori(0, pd->getNumParticles()){
      pos.raw()[i] = make_real4(make_real3(sys->rng().uniform3(-0.5, 0.5))*L, 0);
    }
  }

  fori(0,3000){
    bdhi->forwardTime();
    auto pos = pd->getPos(access::location::cpu, access::mode::read);
    real4 *p = pos.raw();
    out<<"#"<<endl;
    forj(0,pd->getNumParticles()){
      out<<std::setprecision(15)<<make_real3(p[j])<<"\n";
    }
  }

  sys->finish();
  return true;
}

void selfDiffusionCubicBox_test(){
  int NL = 10;
  real L_min = 8*rh;
  real L_max = 128*rh;
  int N=4096;
  forj(0, NL){
    real L = L_min + j*((L_max-L_min)/(real)(NL-1));
    idealParticlesDiffusion(N, make_real3(L));
    CudaCheckError();
  }


}

void selfDiffusion_q2D_test(){
  int NL = 30;
  real L_min = 8*rh;
  real L_max = 128*rh;
  real Lx = 32*rh;
  int N=4096;
  std::ofstream out("selfDiffusion_q2D.theo");
  forj(0, NL){
    double Lz = L_min + j*((L_max-L_min)/(real)(NL-1));
    idealParticlesDiffusion(N, make_real3(Lx, Lx, Lz), "q2D.Lx"+std::to_string(Lx)+".test");
    double L = Lx;
    
    long double M0 = 1.0L/(6.0L*M_PIl*viscosity*rh);
    //From eq 21 and 23 in Vögele, M., & Hummer, G. (2016). Divergent Diffusion Coefficients in Simulations of Fluids and Lipid Membranes. The Journal of Physical Chemistry B, 120(33), 8722–8732. doi:10.1021/acs.jpcb.6b05102
  
    double Mplane_near = M0 + M0/L*(M_PI*0.5*Lz/L - 4.3878);
    double Mplane_far = M0 + M0/Lz*(1.5*log(L/Lz) - 2.8897);
    
    double Mperp_near = M0 + M0/Lz*(3*log(L/Lz) - 2.77939);
    double Mperp_far = M0 - 2.9252/(6*M_PI*viscosity*L);

    out<<std::setprecision(15)<<Lz/rh<<" "<<Mplane_near/M0<<" "<<Mplane_far/M0<<" ";
    out<<std::setprecision(15)<<Mperp_near/M0<<" "<<Mperp_far/M0<<endl;
    
    CudaCheckError();
  }


}


//Returns Var(noise)
double3 singleParticleNoise(real T, real3 L){
  int N = 1;
  auto sys = make_shared<System>();
  sys->rng().setSeed(1234791);
  auto pd = make_shared<ParticleData>(N, sys);
  auto pg = make_shared<ParticleGroup>(pd, sys, "All");

  Box box(L);
  BDHI::FCM::Parameters par;
  par.temperature = T;
  par.viscosity = viscosity;
  par.hydrodynamicRadius = rh;
  par.dt = 1.0;
  par.box = box;
  par.tolerance = tolerance;

  auto bdhi = make_shared<BDHI::EulerMaruyama<BDHI::FCM>>(pd, pg, sys, par);
  double3 prevp;
  {
    auto pos = pd->getPos(access::location::cpu, access::mode::write);
    pos.raw()[0] = make_real4(make_real3(sys->rng().uniform3(-0.5, 0.5))*box.boxSize, 0);
    prevp = make_double3(pos.raw()[0]);
  }
  double3 variance = make_double3(0);
  double3 mean = make_double3(0);
  int nsteps = 10000;
  fori(0,nsteps){
    bdhi->forwardTime();
    auto pos = pd->getPos(access::location::cpu, access::mode::read);
    real4 *p = pos.raw();
    double3 noise = make_double3(p[0]) - prevp;   
    double3 delta = noise - mean;
    mean += delta/double(i+1);
    double3 delta2 = noise - mean;
    variance += delta*delta2;    
    prevp = make_double3(p[0]);
  }
  variance /= real(nsteps);
  
  sys->finish();

  return variance;
}


void noiseVariance_test(){
  int NL = 10;
  real L_min = 4.0*rh;
  real L_max = 128.0*rh;

  real T = temperature;  
  std::ofstream out("noiseVariance.test");  

  forj(0, NL){
    real L = L_min + j*((L_max-L_min)/(real)(NL-1));
    real selfDiffusion = T*computeM0PBC(L);
    double3 noiseCorr = singleParticleNoise(T, make_real3(L));
    //This should be close to 1 in the three directions
    out<<std::setprecision(15)<<L/rh<<" "<<noiseCorr.x/(2*selfDiffusion)<<" "<<noiseCorr.y/(2*selfDiffusion)<<" "<<noiseCorr.z/(2*selfDiffusion)<<endl;
    CudaCheckError();
  }

}


using namespace std;
int main( int argc, char *argv[]){

  temperature = std::stod(argv[2]);
  viscosity = std::stod(argv[3]);
  rh = std::stod(argv[4]);
  tolerance = std::stod(argv[5]);
  if(strcmp(argv[1], "selfMobilityCubicBox")==0) selfMobilityCubicBox_test();
  if(strcmp(argv[1], "pairMobilityCubicBox")==0){
    pairMobilityCubicBox_test(2*rh);
    pairMobilityCubicBox_test(4*rh);
    pairMobilityCubicBox_test(6*rh);
  }
  if(strcmp(argv[1], "pairMobility_q2D")==0){
    pairMobility_q2D_test(2*rh);
    pairMobility_q2D_test(4*rh);
    pairMobility_q2D_test(6*rh);
  }

  if(strcmp(argv[1], "selfMobility_q2D")==0) selfMobility_q2D_test(); 
  if(strcmp(argv[1], "selfDiffusionCubicBox")==0) selfDiffusionCubicBox_test();
  if(strcmp(argv[1], "selfDiffusion_q2D")==0) selfDiffusion_q2D_test();
  if(strcmp(argv[1], "noiseVariance")==0) noiseVariance_test();
  return 0;
}
