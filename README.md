# Assumptions:
- Not to use the default camera application
- Not to use an ML framework, or a backend
- Utilize ARCore or something similar

# Issues:
- Flutter doens't have official implementations for ARCore, so the flutter native interface had to be used.
- Limited time on optimizing the algorithm used for detecting the contours and edges
- Not enough time to implement realtime object creation, a lot of time was lost in making ARCore work with flutter and a fever to add to it.
