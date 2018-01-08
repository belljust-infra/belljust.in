---
title: "Thrust Mapper - Finding a Solution"
date: 2018-01-08T13:07:05-04:00
---

[Last post](https://belljust.in/posts/thrust-mapper/thrust-mapper/), we defined a couple matrices which map thruster forces to forces on the robot.

$$
    A =
    \begin{bmatrix}
        0       & 1       & 0       & 1 \\\\\\
        1       & 0       & 1       & 0 \\\\\\
        r\_{5z} & r\_{6z} & -r\_{7z} & -r\_{8z} \end
    {bmatrix}, \quad
    B =
    \begin{bmatrix}
        r\_{1x}  & r\_{2x} & -r\_{3x}  & -r\_{4x} \\\\\\
        -r\_{1y} & -r\_{2y} & r\_{3y}  & r\_{4y} \\\\\\
        1        & 1         & 1          & 1
    \end{bmatrix}
$$

$$
A
    \begin{bmatrix}
        T_5 \\\\\\
        T_6 \\\\\\
        T_7 \\\\\\
        T_8 \end
    {bmatrix} =
    \begin{bmatrix}
        F_x \\\\\\
        F_y \\\\\\
        M_z
    \end{bmatrix}, \quad
B
    \begin{bmatrix}
        T_1 \\\\\\
        T_2 \\\\\\
        T_3 \\\\\\
        T_4 \end
    {bmatrix} =
    \begin{bmatrix}
        M_x \\\\\\
        M_y \\\\\\
        F_z \end
    {bmatrix}
$$

## The Inverse

If you remember your first linear algebra course, you'll know that we need the inverses of \\(A\\) and \\(B\\) to find the thruster forces that gives us a solution.

$$
A^\{-1} 
    \begin{bmatrix}
        F_x \\\\\\
        F_y \\\\\\
        M_z \end
    {bmatrix} =
    \begin{bmatrix}
        T_5 \\\\\\
        T_6 \\\\\\
        T_7 \\\\\\
        T_8 \end
    {bmatrix}
$$

But \\(A\\) isn't a square matrix so it does _not_ have an inverse!
This actually makes sense if we look at the physical system.
If there was an inverse, it would imply that there is a unique solution to every system.

![Yaw maneuver using 2 different configurations](/img/thrust-mapper/AUV_Spin.png#center)

The figure above illustrates the robot doing a yaw maneuver - spinning about the z-axis - using two configurations.
On the left, only the bow and stern thrusters are used.
On the right, only the port and starboard thrusters are used.[^1]

In fact, we can redistribute this effort between these thrusters in an infinite number of ways to get the same overall effect.
So no, A is not invertible, but there are many solutions.
This where the pseudo-inverse, \\(A^+\\) comes in handy.

## The pseudo-Inverse

I won't go into all [the details of pseudo-inverses](https://en.wikipedia.org/wiki/Moore%E2%80%93Penrose_inverse) here but, for our purposes, it's helpful to note these facts:

if \\(Ax=b\\) has \\(> 1\\) solutions then \\(x = A^+b\\)

\\(A^+\\) is unique

\\(A^+\\) exists for all \\(A\\)

The popular python matrix library, `numpy`, comes with a function for obtaining the pseudo-inverse, `numpy.linalg.pinv`

```python
from numpy import matrix
from numpy.linalg import pinv

A = matrix([1,   1,   0,   0],
           [0,   0,   1,   1],
           [r5z, 56z, 57z, r8z])
Ap = pinv(A)
```

Now, whenever we want to find the equivalent thruster forces to get a desired response, we let numpy do the heavy lifting.
For example, if we want the robot to dive deeper while accelerating forward, we might do this:

```python
# create the desired response as a vector
Fx_Fy_Mz = matrix([1, 0, 1]).T
T5678    = Ap * Fx_Fy_Mz
```

And voilá, `T5678` contains a vector for the thrusts required of thrusters 5, 6, 7, and 8 to perform our maneuver.

[^1]: Looking towards the front of a vessel, the nautical terms _bow, stern, port, and starboard_ mean _forward, backward, left, and right_ respectively
