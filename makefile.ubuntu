NETCDF_INC=/usr/include
NETCDF_LIB=/usr/lib/x86_64-linux-gnu
CRTM_DIR=/home/yxl232/lib/crtm_v2.2.3

all: crtm.exe main_crtm.o module_netcdf.o mpi_module.o

crtm.exe: main_crtm.o module_netcdf.o mpi_module.o
	mpif90 -o crtm.exe mpi_module.o module_netcdf.o main_crtm.o -L$(CRTM_DIR)/lib -lcrtm -L$(NETCDF_LIB) -lnetcdf -lnetcdff

mpi_module.o: mpi_module.f
	mpif90  -c -ffree-form mpi_module.f

module_netcdf.o: module_netcdf.f
	mpif90  -c -I$(NETCDF_INC) module_netcdf.f

main_crtm.o: main_crtm.f90 module_netcdf.o mpi_module.o
	mpif90  -c -ffree-form -I$(NETCDF_INC) -I$(CRTM_DIR)/include main_crtm.f90

clean:
	rm *.o *.mod crtm.exe
