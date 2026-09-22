clc
clear
close all

% Geometry's constants
s = 0.40; % Space between two pipes in U shape format
L = 0.5; % Lenght of concrete
d = 0.020; % Pipes mean Diameter 
th = 0.002; % Thickness of the Pipes

% Geometry Construction 
inner_radius = (s - d) / 2; % Inner diameter of the Pipe
outer_radius = (s + d) / 2; % Outer diameter of the Pipe
inner_radius_1 = inner_radius + th;
outer_radius_1 = outer_radius - th;

% Create Geometry
% Define the sector parts
sector1 = regions.sector([0, 0], inner_radius, outer_radius, [180, 360]) - regions.sector([0, 0], inner_radius_1, outer_radius_1, [180, 360]); % creates the hollow U shape section of the Pipe

% Define the rectangular parts
Part1 = regions.rect([-s / 2, L / 2], [d, L]) - regions.rect([-s / 2, L / 2], [d - 2 * th, L]); % create the hollow rectangular section of the pipe in left side
Part2 = regions.rect([s / 2, L / 2], [d, L]) - regions.rect([s / 2, L / 2], [d - 2 * th, L]); % create the hollow rectangular section of the pipe in right side

% Combine parts to create Tube
Tube = sector1 + Part1 + Part2;
Tube.Name = 'PEX';

% Define additional parts for Water domain
Part3 = regions.rect([-s / 2 , L / 2], [d - 2 * th, L]) + regions.rect([s / 2, L / 2], [d - 2 * th, L]); % Define the region for water inside the tube in the rectangular part
part4 = regions.sector([0, 0], inner_radius_1, outer_radius_1, [180, 360]); % Define the region for water inside the tube in the rectangular part in the U shape part

% Combine parts to create Water
Water = Part3 + part4;
Water.Name = 'Water';

% Define Concrete domain
part5 = regions.rect([0, 0], [L + outer_radius, 2*L]);
Concrete = part5 - Tube - Water;
Concrete.Name = 'Concrete';

Domain = Concrete + Tube + Water; 

Domain(1) = Concrete; 
Domain(2) = Tube; 
Domain(3) = Water; 

figure(1) 
title('Geometrical regions')
Domain.draw
axis equal

% Thermo-Fluid Dynamic Parameters 

cp_water = 4186; %J/(Kg*K)            
rho_water = 1000; %kg/m^3    
lambda_water = 0.621; %W/(m*K)     
cp_concrete = 840; %J/(kg*K)
rho_concrete = 2200; %kg/m^3       
lambda_concrete = 2.00; %W/(m*K)
lambda_pex = 0.35; % W/(m*K)
rho_pex = 945; %kg/m^3
cp_pex = 2300; %J/(kg*K)

K = 6.53e-4;   % For itirating the amount of K at first we consider the water viscosity at (40 Celcius) and by calculating the temperature of the outlet we can modify it. This amount is the modification factor of K.

% Boundary Conditions ( Pressure in Pa) 
p_in = 1.01e5;
p_out = 0.96e5;

% Apply B.C. to the velocity domain
Water.Borders.Bc(:) = boundaries.neumann(0); % Assign homogeneous Neumann to all nodes in the water domain
Water.Borders.Bc(34) = boundaries.dirichlet(p_in); % Since the half of the U shape part will be Bc(16) the full U shape part in outer diameter will end at Bc(32) and the rectagular part is Bc(33) so the inlet will be Bc(34)
Water.Borders.Bc(69) = boundaries.dirichlet(p_out); % Since the half of the U shape part will be Bc(51) the  full U shape part in inner diameter will end at Bc(67) and the rectagular part is Bc(68) so the inlet will be Bc(69)

figure(2)
Water.draw('bc')
axis equal
title("Boundary conditions");

Water.mu = K; % associate K with the viscosity coefficient of water
meshArea1 = 1e-4;      
Me = mesh2D(Water, meshArea1); % Mesh Construction

figure(3)
title('Velocity Mesh')
Me.draw
axis equal

% ASSEMBLY AND SOLUTION 

% Construct stiffness matrix and force vector
D_pressure = FemAssembler.BuildStiffness(Me); % Creating the Stiffness Matrix.
b_pressure = FemAssembler.BuildDirichlet(Me); % We have no force and non-homogeouns dirichlet boundary condition.

% Solve the velocity problem
u_pressure = D_pressure \ b_pressure; % Solve the problem.
u_pressure = Me.copyToAllNodes(u_pressure); % Copying the solution to all Nodes.

figure(4)
title('Pressure Distribution')
Me.draw(u_pressure)
shading interp; % Use this to remove the Meshes in the final figure.
title("Pressure [Pa]")

[vx, vy] = Me.gradient(-K * u_pressure); % According to Stokes law the velocity is the gradient of pressure multiplied by constant (-K)

figure(5)
quiver(Me.Nodes.X, Me.Nodes.Y, vx, vy);
axis equal
title('Velocity (m/s)')

v_inlet = abs(vy(1)); % Amount of velocity at Inlet and we use the vy because the Pipes are in Y direction.
v_outlet = abs(vy(end)); % Amount of velocity at Outlet and we use the vy because the Pipes are in Y direction.

% HEAT EQUATION 
% According to the slides, we know that heat equation consits from three
% part. The Unsteady part is in Mass Matrix, the diffusion part is in
% stiffness matrix and the convection part which is the velocity multiplied the temperature gradient.

% Thermal conductivity: Diffusive term 
Concrete.mu = lambda_concrete;
Tube.mu = lambda_pex;
Water.mu = lambda_water;

% Density: Unsteady term 
Concrete.rho = rho_concrete * cp_concrete;
Tube.rho = rho_pex * cp_pex;
Water.rho = rho_water * cp_water;

% Beta: Convective term 
Water.beta = @(x, y) ([Me.interpolate(vx, [x, y]), Me.interpolate(vy, [x, y])]); % The interpolation is used to linearize the velocity with respect to coordinates.
Tube.beta = [0, 0];
Concrete.beta = [0, 0];

T_in_water = 273.15 + 40; % Water inlet temperature (40°C)

% Update boundary conditions on domains by specifying all nodes as DOF
% Apply boundary conditions considering thermal exchanges between 
% coils, concrete, and external environment

for k = 1:length(Domain) % For all the domains which are three domains in our case: water , concrete, Pipe.
    for d = 1:length(Domain(k).Borders) % Different Boarders of the domains.
        Domain(k).Borders(d).Bc(:) = boundaries.none; %  Assigning the none boundary condition to all nodes.
    end
end
% The above loop is used to reset all the boundary conditions which were set in previous section for solving the velocity.

Domain(1).Borders(1).Bc(34) = boundaries.neumann(0); % Top boundary Between the U shape part of the control volume.
Domain(1).Borders(2).Bc(1) = boundaries.neumann(0); % Bottom boundary of the Control Volume.
Domain(1).Borders(2).Bc(3) = boundaries.neumann(0); % Top-Left side of the Pipe
Domain(1).Borders(2).Bc(38) = boundaries.neumann(0); % Top-right side of the pipe

Domain(1).Borders(2).Bc(2) = boundaries.periodic(@(x, y) [-x, y]); % Since we only consider one part of the repeated section the boundaries are periodic.
Domain(1).Borders(2).Bc(39) = boundaries.periodic(@(x, y) [-x, y]); % Since we only consider one part of the repeated section the boundaries are periodic.

Domain(2).Borders(2).Bc(34) = boundaries.neumann(0); % Internal part of the pipe Inlet
Domain(2).Borders(1).Bc(34) = boundaries.neumann(0); % External part of the pipe at Inlet
Domain(2).Borders(2).Bc(69) = boundaries.neumann(0); % Internal part of the pipe at Outlet
Domain(2).Borders(1).Bc(69) = boundaries.neumann(0); % External part of the pipe at Outlet

Domain(3).Borders(1).Bc(69) = boundaries.neumann(0); % Ouput of the water domain
Domain(3).Borders(1).Bc(34) = boundaries.dirichlet(T_in_water); % Input of the water domain

figure(6)
Domain.draw('Bc')
axis equal
title("Boundary Conditions for the temperature problem")

Me2 = mesh2D(Domain, meshArea1);

figure(7)
title('Temperature Mesh')
Me2.draw
axis equal

% Stationary Problem 
% ASSEMBLY AND SOLUTION 

T_air = 273.15 + 25; % Room temperature (25°C)
T_floor = 273.15 + 10; % Floor temperature (10°C)

% Convective heat transfer coefficients W/m^2*K
alpha_floor = 10;
alpha_air = 15;

% Loop to assign the value of sigma to each domain as the sum
% of the two h
for k = 1:length(Domain)
    Domain(k).sigma = (alpha_air + alpha_floor);
end

f = @(x, y) alpha_air * T_air + alpha_floor * T_floor; % Forcing term (constant)

A_temperature = FemAssembler.BuildStiffness(Me2); % Stiffness matrix for the temperature problem, including diffusion and reaction terms
b_temperature = FemAssembler.BuildDirichlet(Me2); 
[A_temperature, b_temperature] = FemAssembler.AddStabilization(Me2, A_temperature, b_temperature); % This command will refine mesh area in order to avoid oscillating solutions at boundaries.

b = FemAssembler.BuildForce(Me2, f, b_temperature); % Here we have homogeneous Neumann conditions, so we don't use BuildNeumann in the right-hand term

T_stationary = Me2.copyToAllNodes(A_temperature \ b); % Steady-state solution

figure(8)
Me2.draw(T_stationary)
title('3D Distribution of the Temperature')
shading interp
hold off

% Transient solution ( Implicit Euler)
M = FemAssembler.BuildMass(Me2); % Mass matrix

dt = 5 * 60 ; % Time step of 1 minutes 
Tend = 12 * 60 * 60; % Final time = 12 hours 

dofs = max(Me2.Nodes.Dof); % number of degrees of freedom
S = M + (dt * A_temperature); % Coefficient of the next time step temperature
T = (10 + 273.15) * ones(dofs, 1); % initial temperature

% Calculating the variation of the Temperature of all nodes in the mesh according to Implicit Euler Method  

for k = 1:Tend/dt 
     t = k * dt;
     T = S \ (M * T + dt * b);
     figure(9)
     Me2.draw(Me2.copyToAllNodes(T),'hidemesh')
     hold off;
     zlim([270 350]);
     view([0, 90]);
     title(['t = ', num2str(t / 3600), ' hours']);
     shading interp
     drawnow();
end